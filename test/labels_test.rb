# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Localized labels (0.9.2): colors, kinds and body types in en/es.
  class LabelsTest < TestCase
    def test_color_options_in_spanish_keep_the_slug_and_the_order
      es = Vehicles.color_options(locale: :es)

      assert_equal Vehicles.colors.map(&:slug), es.map(&:last)
      assert_equal %w[Blanco Negro Gris Plata Azul Rojo Verde Marrón Beige Naranja Amarillo Dorado Morado Otro],
                   es.map(&:first)
      assert_equal Vehicles.color_options, Vehicles.color_options(locale: :en)
    end

    def test_locales_fold_and_fall_back
      assert_equal "Rojo", Vehicles.color("red").label("es-MX")
      assert_equal "Rojo", Vehicles.color("red").label(:es_ES)
      assert_equal "Red", Vehicles.color("red").label(:fr) # no French yet: English
      assert_equal "Red", Vehicles.color("red").label(nil)
    end

    def test_spanish_input_resolves_to_the_slug
      {
        "Rojo" => "red", "marrón" => "brown", "MARRON" => "brown", "gris" => "grey", "blanca" => "white",
        "plateado" => "silver", "azul marino" => "blue", "granate" => "red", "Otro" => "other"
      }.each { |typed, slug| assert_equal slug, Vehicles.color(typed)&.slug, typed }
      assert_nil Vehicles.color("rojizo")
    end

    def test_every_color_has_every_locale
      Labels::LOCALES.each do |locale|
        assert_equal Colors::ALL.map(&:slug).sort, Labels::COLORS[locale].keys.sort
      end
    end

    def test_kind_labels
      assert_equal "Furgoneta", Vehicles.kind_label(:van, locale: :es)
      assert_equal "Van", Vehicles.kind_label("van")
      assert_nil Vehicles.kind_label(:plane)
      assert_equal Vehicles.kinds.map(&:to_s).sort, Vehicles.kind_options(locale: :es).map(&:last).sort
      assert_equal "Autobús", Vehicles.kind_options(locale: :es).first.first # sorted by label
    end

    def test_body_type_labels_cover_the_vocabulary
      Labels::LOCALES.each do |locale|
        assert_equal Model::BODY_TYPES.map(&:to_s), Vehicles.body_type_options(locale: locale).map(&:last)
        assert(Vehicles.body_type_options(locale: locale).all? { |label, _| label })
      end
      assert_equal "Familiar", Vehicles.body_type_label(:wagon, locale: :es)
      assert_equal "Monovolumen", Vehicles.body_type_label("mpv", locale: :es)
    end

    def test_every_kind_in_the_data_has_a_label
      Vehicles.kinds.each { |k| Labels::LOCALES.each { |l| refute_nil Labels::KINDS[l][k.to_s], "#{l} #{k}" } }
    end
  end
end
