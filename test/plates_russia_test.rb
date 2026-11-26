# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Russia (ru). The serials are the examples printed in ГОСТ Р 50577-2018
  # приложение А and the instrument's own structure strings; no real plate is
  # in this file. Russian plates print twelve CYRILLIC letters that look like
  # Latin ones; the dataset writes them as their Latin twins and publishes the
  # map, and Jurisdiction#fold applies it, so both spellings resolve alike.
  class PlatesRussiaTest < TestCase
    def best(serial) = Vehicles.plate(serial, jurisdiction: :ru).best&.id

    def test_russia_loads
      ru = Vehicles.plates(:ru)
      ids = ru.series.map(&:id)

      # Jurisdiction#series puts standard-class series first, oldest first, so
      # the recall-only Soviet series precede the current one there; a strict
      # hit always outranks them in Match#best.
      assert_equal "ru-standard-1994", ru.series.find(&:strict?).id
      assert_operator ids.size, :>=, 30
      %w[ru-taxi-1994 ru-diplomatic-1994 ru-police-1994 ru-transit-1994 ru-ussr-private-1980].each do |id|
        assert_includes ids, id
      end
      assert_equal 12, ru.homoglyph_fold.size
      assert_equal "Y", ru.homoglyph_fold["У"]
    end

    def test_cyrillic_and_latin_spellings_resolve_alike
      {
        "М 976 ММ 77" => "M976MM77", "а123вс77" => "A123BC77", "А 123 ВС 777" => "A123BC777",
        "ОМ 958 99" => "OM95899", "Т ММ 976 78" => "TMM97678", "М 9768 77" => "M976877"
      }.each do |cyrillic, latin|
        cyr = Vehicles.plate(cyrillic, jurisdiction: :ru)
        lat = Vehicles.plate(latin, jurisdiction: :ru)

        assert_predicate cyr, :strict?, cyrillic
        assert_equal lat.series.map(&:id), cyr.series.map(&:id), cyrillic
        assert_equal lat.formatted, cyr.formatted, cyrillic
      end
    end

    def test_series_by_shape
      assert_equal "ru-standard-1994", best("A 123 BC 77")
      assert_equal "ru-standard-1994", best("A 123 BC 777")
      assert_equal "ru-taxi-1994", best("ОМ 958 99")
      assert_equal "ru-diplomatic-head-1994", best("876 CD 2 99")
      assert_equal "ru-diplomatic-1994", best("876 D 234 99")
      assert_equal "ru-export-1994", best("T MM 976 78")
      assert_equal "ru-transit-1994", best("OM 958 M 99")
      assert_equal "A 123 BC 77", Vehicles.plate("а123вс77", jurisdiction: :ru).formatted
    end

    def test_letters_outside_the_twelve_are_not_folded_or_issued
      # Б and Д have no Latin twin; Latin letters outside the twelve (R, S, V)
      # never appear on a current plate; the phonetic reading of В С is "VS".
      ["Б123ВС77", "876 Д 234 99", "A123VS77", "R123BC77"].each do |typed|
        refute_predicate Vehicles.plate(typed, jurisdiction: :ru), :strict?, typed
      end
      refute_predicate Vehicles.plate("A123BC00", jurisdiction: :ru), :strict?
      refute_predicate Vehicles.plate("A123BC077", jurisdiction: :ru), :strict?
    end

    def test_three_digit_codes_only_on_the_ordinary_plate
      assert_equal "ru-standard-1994", best("A123BC799")
      # "ОМ 958 799" is not a taxi plate (two digits only there); the same
      # characters are a valid trailer string "ОМ 9587 99", which is correct.
      refute_includes Vehicles.plate("OM958799", jurisdiction: :ru).series.map(&:id), "ru-taxi-1994"
      refute_predicate Vehicles.plate("OM958M799", jurisdiction: :ru), :valid?
    end

    def test_region_codes_decode
      regions = Plates.decode_table("ru-regions")["regions"]
      by_code = regions.each_with_object({}) { |r, h| r["codes"].each { |c| h[c] = r } }

      assert_equal "г. Москва", by_code["77"]["subject"]
      assert_equal "г. Москва", by_code["777"[1..]]["subject"]
      assert_equal %w[50 90], by_code["50"]["codes"]
      assert_equal %w[20 91], (1..99).map { |i| format("%02d", i) } - by_code.keys
    end

    def test_region_code_history_survives_reassignment
      perm = Plates.decode_table("ru-regions")["regions"].find { |r| r["subject"] == "Пермский край" }

      assert_equal({ "code" => "81", "from" => 2017, "to" => 2020 },
                   perm["code_history"].find { |h| h["code"] == "81" }.slice("code", "from", "to"))
    end

    def test_diplomatic_codes_decode
      codes = Plates.decode_table("ru-diplomatic-codes")["codes"]
      current = codes.reject { |c| c.dig("period", "end") }.to_h { |c| [c["code"], c] }

      assert_equal "United Kingdom", current["001"]["name_en"]
      assert_equal "Республика Гондурас", current["171"]["name"]
      assert_equal "honorary-consular", current["900"]["kind"]
      assert_equal(2, codes.count { |c| c["code"] == "171" })
    end
  end
end
