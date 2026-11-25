# frozen_string_literal: true

# A small recursive-descent parser: short cursor names (i, ch) and one
# case-per-construct method are the clearest form here.
# rubocop:disable Metrics/AbcSize, Naming/MethodParameterName

module Vehicles
  # Generates serials from a plates regex (the dataset's subset: literals,
  # escapes, character classes, (?:...) and (...) groups, alternation, and
  # the quantifiers ? * + {m} {m,} {m,n}), for property tests. It covers the
  # regex's choice points systematically rather than randomly: one serial
  # with every choice at its first option (quantifiers at their minimum, the
  # first branch), one with every choice at its last (quantifiers at their
  # maximum, * and + capped at 3), and, for every choice point and every
  # option it has, one serial with that point set to that option. So every
  # optional group is seen present and absent, every branch is taken, and
  # every quantifier is seen at its bounds.
  module RegexSamples
    ALPHABET = [*"A".."Z", *"0".."9"].freeze
    MAX_REPEAT = 3
    SEQ_END = ["|", ")"].freeze
    SEPARATORS = [" ", "-", "·", "."].freeze

    module_function

    def samples(source, seed: 0)
      ast = parse(source.delete_prefix("\\A").delete_suffix("\\z"))
      return [] if ast.nil?

      counter = [0]
      generate(ast, ->(_i, _n) { 0 }, Random.new(seed), counter)
      points = counter[0]
      out = %i[first last].map do |mode|
        run(ast, seed, ->(_i, n) { mode == :first ? 0 : n - 1 })
      end
      # Option counts per point, read from a first-option pass.
      sizes = []
      generate(ast, lambda { |i, n|
        sizes[i] = n
        0
      }, Random.new(seed), [0])
      points.times do |p|
        (sizes[p] || 1).times do |o|
          out << run(ast, seed + p + o, ->(i, _n) { i == p ? o : 0 })
        end
      end
      out.compact.uniq
    end

    def run(ast, seed, policy)
      generate(ast, policy, Random.new(seed), [0])
    end

    # --- parsing -----------------------------------------------------------
    # Node forms: [:seq, [items]], [:alt, [seqs]], [:char, str], [:class, chars],
    # [:rep, node, min, max]. Returns nil for constructs it does not model.
    def parse(src)
      chars = src.chars
      node, rest = parse_alt(chars, 0)
      rest == chars.size ? node : nil
    rescue ArgumentError
      nil
    end

    def parse_alt(chars, i)
      seqs = []
      seq, i = parse_seq(chars, i)
      seqs << seq
      while i < chars.size && chars[i] == "|"
        seq, i = parse_seq(chars, i + 1)
        seqs << seq
      end
      [seqs.size == 1 ? seqs.first : [:alt, seqs], i]
    end

    def parse_seq(chars, i)
      items = []
      while i < chars.size && !SEQ_END.include?(chars[i])
        atom, i = parse_atom(chars, i)
        atom, i = parse_quantifier(atom, chars, i)
        items << atom
      end
      [[:seq, items], i]
    end

    def parse_atom(chars, i)
      ch = chars[i]
      case ch
      when "("
        look = chars[i + 1] == "?" && ["=", "!"].include?(chars[i + 2])
        raise ArgumentError, "unsupported group" if chars[i + 1] == "?" && !look && chars[i + 2] != ":"

        j = chars[i + 1] == "?" ? i + 3 : i + 1
        node, j = parse_alt(chars, j)
        raise ArgumentError, "unclosed" unless chars[j] == ")"

        # A lookaround constrains without consuming: generate nothing for it
        # (samples that break it simply do not match and are not checked).
        [look ? [:seq, []] : node, j + 1]
      when "["
        j = i + 1
        j += 1 while j < chars.size && (chars[j] != "]" || j == i + 1)
        body = chars[(i + 1)...j].join
        [[:class, class_members(body)], j + 1]
      when "\\"
        [escape(chars[i + 1]), i + 2]
      when "."
        [[:class, ALPHABET], i + 1]
      when "^", "$"
        raise ArgumentError, "anchor"
      else
        [[:char, ch], i + 1]
      end
    end

    def escape(ch)
      case ch
      when "d" then [:class, ALPHABET.grep(/\d/)]
      when "w" then [:class, ALPHABET]
      when "s" then [:char, " "]
      when "A", "z", "Z", "b" then [:seq, []]
      else [:char, ch]
      end
    end

    def class_members(body)
      re = Regexp.new("[#{body}]")
      members = ALPHABET.grep(re)
      members = SEPARATORS.grep(re) if members.empty?
      raise ArgumentError, "empty class" if members.empty?

      members
    end

    def parse_quantifier(atom, chars, i)
      case chars[i]
      when "?" then [[:rep, atom, 0, 1], skip_lazy(chars, i + 1)]
      when "*" then [[:rep, atom, 0, MAX_REPEAT], skip_lazy(chars, i + 1)]
      when "+" then [[:rep, atom, 1, MAX_REPEAT], skip_lazy(chars, i + 1)]
      when "{"
        j = (i...chars.size).find { |k| chars[k] == "}" } or raise ArgumentError, "brace"
        lo, hi = chars[(i + 1)...j].join.split(",", -1)
        min = lo.to_i
        max = if hi.nil?
                min
              elsif hi.empty?
                min + MAX_REPEAT
              else
                hi.to_i
              end
        [[:rep, atom, min, max], skip_lazy(chars, j + 1)]
      else
        [atom, i]
      end
    end

    def skip_lazy(chars, i)
      chars[i] == "?" ? i + 1 : i
    end

    # --- generation --------------------------------------------------------
    def generate(node, policy, rng, counter)
      case node[0]
      when :seq then node[1].map { |n| generate(n, policy, rng, counter) }.join
      when :char then node[1]
      when :class then node[1][rng.rand(node[1].size)]
      when :alt
        idx = counter[0]
        counter[0] += 1
        generate(node[1][policy.call(idx, node[1].size)], policy, rng, counter)
      when :rep
        _, inner, min, max = node
        times = min
        if max > min
          idx = counter[0]
          counter[0] += 1
          times = policy.call(idx, 2).zero? ? min : max
        end
        Array.new(times) { generate(inner, policy, rng, counter) }.join
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Naming/MethodParameterName
