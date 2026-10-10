# frozen_string_literal: true

require "test_helper"

module Vehicles
  # 0.7.8: misspelled makes resolve (bounded edit distance, never a guess
  # between equally close makes), and top_models(country:) orders by that
  # country's own rank instead of the global decile.
  class TypoAndCountryRankTest < TestCase
    # --- typo tolerance ------------------------------------------------------

    def test_marcedes_resolves_to_mercedes_benz
      # From production logs: a mechanic typed this twice and got nothing.
      assert_equal "mercedes-benz", Vehicles.make("marcedes")&.slug
    end

    def test_volkswagon_resolves_to_volkswagen
      assert_equal "volkswagen", Vehicles.make("Volkswagon")&.slug
    end

    def test_a_tie_between_two_makes_returns_nil
      # "acra" is ONE edit from both Acura and Acma (dataset 2026.10): two
      # different makes equally close — the answer must be nil, never a pick.
      ds = Vehicles.dataset
      tied = ds.send(:fuzzy_keys).select { |k, _m| Fuzzy.distance("acra", k, 1) == 1 }

      assert_equal %w[acma acura], tied.map { |_k, m| m.slug }.uniq.sort, "fixture: the tie must be real"
      assert_nil Vehicles.make("Acra")
    end

    def test_exact_and_alias_matches_win_over_fuzzy
      assert_equal "mercedes-benz", Vehicles.make("Mercedes")&.slug # built-in alias
      assert_equal "seat", Vehicles.make("Seat")&.slug              # not "Skeet" or similar
      assert_equal "kia", Vehicles.make("kia")&.slug
    end

    def test_fuzzy_false_is_exact_only
      assert_nil Vehicles.make("marcedes", fuzzy: false)
      assert_nil Vehicles.find("volkswagon golf", fuzzy: false)
    end

    def test_out_of_budget_input_never_matches
      # Regression (codex review): a lone length-compatible key used to be
      # accepted at budget + 1.
      assert_nil Vehicles.make("z" * 28)
      assert_nil Vehicles.make("qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq")
    end

    def test_helpers_forward_the_fuzzy_opt_out
      assert_empty Vehicles.models("marcedes", fuzzy: false)
      refute_empty Vehicles.models("marcedes")
      assert_empty Vehicles.model_options("marcedes", fuzzy: false)
      assert_nil Vehicles.model("marcedes", "sprinter", fuzzy: false)
      assert_equal "Sprinter", Vehicles.model("marcedes", "sprinter")&.name
    end

    def test_short_queries_never_fuzzy_match
      # 3 characters: a one-edit radius is noise (bmw→bmx, kia→kis, …).
      assert_nil Vehicles.make("bnw")
      assert_nil Vehicles.make("kai")
    end

    def test_budget_is_one_edit_below_six_characters
      assert_equal "fiat", Vehicles.make("fiet")&.slug        # 1 edit, 4 chars
      assert_nil Vehicles.make("fete"), "2 edits on 4 characters must not match"
    end

    def test_two_edits_allowed_from_six_characters
      assert_equal "hyundai", Vehicles.make("hyundia")&.slug  # transposition = 2 edits
    end

    def test_free_text_find_retries_a_misspelled_make
      assert_equal "Volkswagen Golf", Vehicles.find("volkswagon golf")&.full_name
      assert_equal "Volkswagen Golf", Vehicles.find("vw golf")&.full_name, "exact pass unchanged"
    end

    def test_validators_stay_exact
      skip "ActiveModel not available" unless defined?(ActiveModel::Model)

      klass = Class.new do
        include ActiveModel::Model

        attr_accessor :make, :model

        def self.name = "Car"
        validates :make, vehicle_make: true
        validates :model, vehicle_model: true
      end

      refute_predicate klass.new(make: "marcedes"), :valid?, "a typo must never validate as a stored make"
      assert_predicate klass.new(make: "Mercedes-Benz"), :valid?
    end

    # --- per-country ranking -------------------------------------------------

    def test_rank_in_reads_the_country_rank
      golf = Vehicles.find("vw golf")

      assert_kind_of Integer, golf.rank_in(:gb)
      assert_equal golf.rank_in(:gb), golf.rank_in("GB"), "case/symbol forgiving"
      assert_nil golf.rank_in(:xx)
    end

    def test_top_models_with_country_follows_that_countrys_rank
      gb = Vehicles.top_models(kind: :car, country: :gb, limit: 50)
      ranks = gb.map { |m| m.rank_in(:gb) }

      refute_includes ranks, nil, "the GB top 50 cars all have a GB rank"
      assert_equal ranks.sort, ranks, "ordered by GB rank, not by global decile"
      assert_equal 1, ranks.first
    end

    def test_country_order_differs_from_the_global_order
      # The bug: a filtered list kept the global sort. Ukraine's top 10 by its
      # own register is not the global top 10 filtered to Ukraine.
      by_rank = Vehicles.top_models(kind: :car, country: :ua, limit: 10).map(&:slug)
      by_global = Vehicles.dataset.all_models
                          .select { |m| m.kind == :car && m.global_decile && m.available_in?(:ua) }
                          .sort_by { |m| [m.global_decile, -m.availability.size, m.name] }
                          .first(10).map(&:slug)

      refute_equal by_global, by_rank
    end

    def test_unranked_in_country_follow_the_ranked_ones
      list = Vehicles.top_models(kind: :car, country: :gb, limit: 100_000)
      seen_unranked = false
      list.each do |m|
        if m.rank_in(:gb).nil?
          seen_unranked = true
        else
          refute seen_unranked, "#{m.full_name} has a GB rank but sorted after an unranked model"
        end
      end
    end

    def test_snapshot_without_country_ranks_keeps_the_global_order
      raw = { "version" => "t", "makes" => [
        { "name" => "A", "slug" => "a", "kinds" => ["car"], "models" => [
          { "name" => "Late", "slug" => "late", "kind" => "car", "global_decile" => 5, "availability" => ["gb"] },
          { "name" => "Early", "slug" => "early", "kind" => "car", "global_decile" => 1, "availability" => ["gb"] }
        ] }
      ] }
      names = Dataset.new(raw).top_models(country: :gb).map(&:name)

      assert_equal %w[Early Late], names
    end
  end
end
