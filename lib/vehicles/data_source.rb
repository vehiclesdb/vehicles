# frozen_string_literal: true

require "json"

module Vehicles
  # Which dataset file this process serves, and when it switches to another.
  # Behind Vehicles.dataset; not called directly.
  #
  # The rules (0.9.2):
  #   - an explicit `Vehicles.data_path=` always wins;
  #   - otherwise a refreshed cache (`config.cache_path`) is served only when
  #     it is USABLE: a schema this gem reads, and not older than the data
  #     bundled in the gem. A cache an older gem left behind loses to a newer
  #     gem's bundled data instead of silently downgrading it;
  #   - every process notices a new file: at most every
  #     `config.reload_check_interval` seconds (default 5) a call stats the
  #     file in effect and the cache, and reloads when either changed. So a
  #     refresh run by a job, another worker or another container (cache on a
  #     shared volume) reaches every web worker without a restart or a hook;
  #   - a file that cannot be read or parsed never replaces the dataset in
  #     memory: the process keeps serving what it has.
  module DataSource
    class Error < StandardError; end

    # Dataset `schema_version`s this gem reads. A payload or cache with any
    # other schema is never loaded or promoted.
    SCHEMA_VERSIONS = [2].freeze

    # How much of a file's start holds "version"/"schema_version" (both open
    # every dist/vehicles.json), so checking a file never parses 8 MB.
    HEADER_BYTES = 4096

    Snapshot = Struct.new(:path, :stamp, :dataset, :checked_at)

    LOCK = Mutex.new

    module_function

    # The Dataset to serve now. Lock-free on the hot path; the stat check and
    # any reload happen under LOCK, once, whoever gets there first.
    def dataset
      snap = @snapshot
      return snap.dataset if snap && !due?(snap)

      LOCK.synchronize { sync }
    end

    def reset!
      LOCK.synchronize do
        @snapshot = nil
        @headers = nil
        @unloadable = nil
      end
    end

    # The file Vehicles.dataset loads (see the rules above).
    def active_path
      return Vehicles.data_path_override if Vehicles.data_path_override

      cache = Vehicles.configuration.cache_path.to_s
      return cache if Vehicles.configuration.use_cache && usable_cache?(cache)

      Vehicles::DATA_PATH
    end

    # A cache file the gem may serve: present, a supported schema, a valid
    # version, and not older than the bundled data.
    def usable_cache?(path)
      return false if path.empty? || !File.file?(path)

      head = header(path)
      bundled = header(Vehicles::DATA_PATH)
      compatible?(head) && head[:version] >= bundled[:version]
    end

    # { version: Gem::Version or nil, schema_version: Integer or nil } of a
    # dataset file, memoized per file stamp (a changed file is re-read).
    def header(path)
      stamp = stamp(path)
      cached = (@headers ||= {})[path]
      return cached[1] if cached && cached[0] == stamp

      parsed = read_header(path)
      @headers[path] = [stamp, parsed]
      parsed
    end

    def compatible?(head)
      SCHEMA_VERSIONS.include?(head[:schema_version]) && !head[:version].nil?
    end

    # "2026.11.2" → Gem::Version, or nil when it is not a version.
    def version(str)
      str = str.to_s
      Gem::Version.correct?(str) && !str.empty? ? Gem::Version.new(str) : nil
    end

    # [mtime, size, inode] — a rename onto the path changes the inode, so a
    # promoted file is noticed even within one mtime tick. nil when missing.
    def stamp(path)
      st = File.stat(path)
      [st.mtime, st.size, st.ino]
    rescue SystemCallError
      nil
    end

    # The newest dataset this app already has: the bundled one, or a usable
    # cache (whatever `use_cache` says — a refresh never writes an older file).
    # (and, unless `data_path=` pins a file, the dataset this process keeps
    # in memory: it never goes back to older data on its own).
    def newest_version
      bundled = header(Vehicles::DATA_PATH)[:version]
      cache = Vehicles.configuration.cache_path.to_s
      cached = usable_cache?(cache) ? header(cache)[:version] : nil
      memory = Vehicles.data_path_override ? nil : version(Vehicles.dataset.version)
      [bundled, cached, memory].compact.max
    end

    # The cache file when another process promoted something newer than what
    # this process has loaded, else the dataset in memory.
    def newest_dataset(path)
      current = Vehicles.dataset
      loaded = version(current.version)
      return current unless usable_cache?(path)
      return current if loaded && header(path)[:version] <= loaded

      build(path)
    end

    # --- internals -----------------------------------------------------------

    def due?(snap, now = clock)
      interval = Vehicles.configuration.reload_check_interval
      !interval.nil? && now - snap.checked_at >= interval.to_f
    end

    def sync
      snap = @snapshot
      now = clock
      return snap.dataset if snap && !due?(snap, now)

      path = active_path
      stamp = stamp(path)
      # Unchanged, the very file that already failed to load, or older than
      # what is in memory (a cache deleted or replaced by an older/unreadable
      # file): keep serving. Only `reload!` goes back to older data.
      if snap && ((snap.path == path && snap.stamp == stamp) || @unloadable == [path, stamp] || older?(path, snap))
        snap.checked_at = now
        return snap.dataset
      end

      load_snapshot(path, stamp, now, snap)
    end

    def older?(path, snap)
      candidate = header(path)[:version]
      current = version(snap.dataset.version)
      current && (candidate.nil? || candidate < current)
    end

    # Parse and fully build a dataset file, or raise: a file that parses but
    # is not a whole dataset (no makes, a malformed model) must fail HERE,
    # not later inside a request.
    def build(path, previous = nil)
      raw = JSON.parse(File.read(path))
      raise Error, "#{path}: no makes" unless raw.is_a?(Hash) && raw["makes"].is_a?(Array) && raw["makes"].any?

      # The header was checked on an earlier read; another process may have
      # replaced the file since. Check what was actually parsed.
      unless path == Vehicles::DATA_PATH || Vehicles.data_path_override
        head = { version: version(raw["version"]), schema_version: raw["schema_version"] }
        raise Error, "#{path}: unusable" unless compatible?(head) &&
                                                head[:version] >= header(Vehicles::DATA_PATH)[:version]
      end

      if previous && !Vehicles.data_path_override && version(raw["version"]) < version(previous.version)
        raise Error, "#{path}: older than the dataset in memory"
      end

      Dataset.new(raw).tap(&:all_models)
    end

    def load_snapshot(path, stamp, now, previous)
      dataset = build(path, previous&.dataset)

      if previous && previous.dataset.version != dataset.version
        Vehicles.logger&.info("[vehicles] dataset #{previous.dataset.version} → #{dataset.version} (#{path})")
      end
      @snapshot = Snapshot.new(path, stamp, dataset, now)
      dataset
    rescue StandardError => e
      raise if path == Vehicles::DATA_PATH && previous.nil? # the gem's own data: a packaging bug, say so

      Vehicles.logger&.warn("[vehicles] could not load #{path} (#{e.class}); keeping the dataset in use")
      @unloadable = [path, stamp]
      if previous
        previous.checked_at = now
        previous.dataset
      else
        load_snapshot(Vehicles::DATA_PATH, stamp(Vehicles::DATA_PATH), now, nil)
      end
    end

    def read_header(path)
      head = File.open(path, "rb") { |f| f.read(HEADER_BYTES) }.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      version = head[/"version"\s*:\s*"([^"]*)"/, 1]
      schema = head[/"schema_version"\s*:\s*(\d+)/, 1]
      if version.nil? || schema.nil? # not at the top: read it the slow way
        raw = JSON.parse(File.read(path))
        version = raw["version"] if raw.is_a?(Hash)
        schema = raw["schema_version"] if raw.is_a?(Hash)
      end
      { version: version(version), schema_version: schema&.to_i }
    rescue StandardError
      { version: nil, schema_version: nil }
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
