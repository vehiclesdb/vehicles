# frozen_string_literal: true

require "test_helper"
require "open3"

module Vehicles
  # The filler against templates VehiclesDB really serves
  # (test/fixtures/plate_templates: GET /plates/:code/:series_id/template.svg,
  # saved from vehiclesdb-web 4ab9d646). Ported from vehiclesdb-web's
  # test/models/plates/template_fill_test.rb.
  class TemplateFillTest < TestCase
    FIXTURES = File.expand_path("fixtures/plate_templates", __dir__)
    Fill = Plates::TemplateFill

    def template(name) = File.read(File.join(FIXTURES, "#{name}.svg"), encoding: "UTF-8")

    def setup
      @spain = template("es-national-2000")
    end

    def test_refuses_to_fill_a_template_with_active_content
      [@spain.sub("<defs>", "<defs><script>alert(1)</script>"),
       @spain.sub('role="img"', 'role="img" onload="alert(1)"'),
       @spain.sub("<defs>", '<defs><svg/onload="alert(1)"></svg>')].each do |bad|
        assert_raises(Fill::Error) { Fill.fill(bad, "1234 BCD") }
      end
      %w[es-national-2000 de-standard-nw fr-siv-standard-75].each do |name|
        assert Fill.inert?(template(name)), "#{name} is not inert"
      end
    end

    def test_fills_upcases_and_drops_the_metadata_block
      out = Fill.fill(@spain, " 1234 bcd ")

      assert_includes out, ">1234 BCD</text>"
      assert_includes out, %(aria-label="Spain plate 1234 BCD")
      refute_includes out, "vdb-template"
    end

    def test_separators_are_free_the_shapes_own_are_printed
      assert_includes Fill.fill(@spain, "1234-BCD"), ">1234 BCD</text>"
      assert_includes Fill.fill(@spain, "1234BCD"), ">1234 BCD</text>"
    end

    def test_refuses_registrations_of_another_shape_and_anything_not_a_character_class
      ["123 BCD", "1234 BC1", "1234 BCD9", "<b>4 BCD", "1234 B&D", ""].each do |bad|
        assert_raises(Fill::Error, bad) { Fill.fill(@spain, bad) }
      end
      assert_raises(Fill::Error) { Fill.fill("<svg/>", "1234 BCD") }
    end

    def test_escapes_what_it_writes
      assert_equal "A&amp;B&lt;&gt;&quot;&#39;", Fill.escape(%(A&B<>"'))
    end

    def test_label_replaces_the_whole_accessible_name_escaped
      out = Fill.fill(@spain, "1234BCD", label: %(Matrícula "1234 BCD"))

      assert_includes out, %(aria-label="Matrícula &quot;1234 BCD&quot;")
      assert_equal 1, out.scan("aria-label=").size
    end

    def test_a_region_template_fills_every_group
      out = Fill.fill(template("fr-siv-standard-75"), "ab123cd")

      assert_equal %w[AB 123 CD], out.scan(%r{<text id="vdb-serial-\d+"[^>]*>([^<]*)</text>}).flatten
      assert_includes out, %(aria-label="France plate AB123CD")
    end

    def test_a_german_seal_template_takes_its_district_shape_only
      germany = template("de-standard-nw")

      assert_includes Fill.fill(germany, "DU-AB 1234"), "DU"
      assert_raises(Fill::Error) { Fill.fill(germany, "D-AB 1234") } # one-letter district: another shape
    end

    def test_a_group_wider_than_its_room_is_squeezed_never_overflowing
      meta = Fill.metadata(template("de-standard-nw"))
      meta["slots"][0]["max_width"] = 10.0
      group = Fill.groups(meta, "WM-WM 8888").first

      assert group[:squeezed]
      assert_in_delta 10.0, group[:text_length]
    end

    def test_shape_of_keeps_classes_and_separators_only
      assert_equal "NNNN LLL", Fill.shape_of("1234 bcd")
      assert_equal "L-NNNN-LL", Fill.shape_of("M-1234-AB")
      assert_equal "LL-LL NNNN", Fill.shape_of("DU-AB  1234")
      assert_nil Fill.shape_of("1234 BÇD")
      assert_nil Fill.shape_of("1234_BCD") # "_" is the URL spelling, not a separator a plate prints
    end

    def test_the_shared_fit_formulas
      assert_in_delta 49.0, Fill.fit_size(100, 50, 100)
      assert_in_delta 91.4, Fill.recentered_baseline(55.0, 101.2, 0.36)
    end

    def test_the_metadata_schema_is_the_one_this_filler_understands
      %w[es-national-2000 fr-siv-standard-75 de-standard-nw].each do |name|
        assert_equal Fill::SCHEMA_VERSION, Fill.metadata(template(name))["version"], name
      end
    end

    # The extraction contract: the file loads and works in a bare Ruby — no
    # Rails, no ActiveSupport, no gems at all, not even the rest of this one.
    def test_runs_in_plain_ruby_without_rails_or_gems
      script = <<~RUBY
        require #{File.expand_path("../lib/vehicles/plates/template_fill.rb", __dir__).inspect}
        print Vehicles::Plates::TemplateFill.fill($stdin.read, "1234 BCD")[/>1234 BCD</] ? "ok" : "no"
        print $LOADED_FEATURES.grep(/active_support|rails|vehicles\\.rb/).empty? ? "-clean" : "-dirty"
      RUBY
      out, status = Open3.capture2("ruby", "--disable-gems", "-e", script, stdin_data: @spain)

      assert_predicate status, :success?
      assert_equal "ok-clean", out
    end
  end
end
