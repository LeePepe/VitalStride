# frozen_string_literal: true

require "base64"
require "json"
require "open3"
require "rbconfig"
require "rubygems"

module FastlaneToolchain
  MINIMUM_VERSION = Gem::Version.new("2.238.0")
  PROBE_ENV = "VITALSTRIDE_FASTLANE_TOOLCHAIN_PROBE"
  BOOTSTRAP_ENV = "VITALSTRIDE_FASTLANE_TOOLCHAIN_BOOTSTRAPPED"
  EVIDENCE_ENV = "VITALSTRIDE_FASTLANE_TOOLCHAIN_EVIDENCE"
  PROBE_MARKER = "VITALSTRIDE_FASTLANE_TOOLCHAIN="

  module_function

  def resolve_path_command(name)
    path = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR, -1).find do |directory|
      directory = "." if directory.empty?
      candidate = File.join(directory, name)
      File.file?(candidate) && File.executable?(candidate)
    end

    raise "#{name} must resolve from unchanged PATH" unless path

    File.expand_path(File.join(path.empty? ? "." : path, name))
  end

  def source_evidence
    {
      "fastlane_libraries" => loaded_features("fastlane.rb"),
      "sigh_libraries" => loaded_features("sigh.rb"),
      "sigh_manager" => Sigh::Manager.method(:start).source_location&.first,
      "provisioning_action" =>
        Fastlane::Actions::GetProvisioningProfileAction.method(:run).source_location&.first
    }
  end

  def loaded_features(basename)
    matches = $LOADED_FEATURES
              .select { |path| File.basename(path) == basename }
              .map { |path| File.realpath(path) }
              .uniq
              .sort
    raise "expected a loaded #{basename}" if matches.empty?

    matches
  end

  def probe_evidence
    gem_spec = Gem.loaded_specs.fetch("fastlane")
    {
      "ok" => true,
      "ruby" => File.realpath(RbConfig.ruby),
      "gem_home" => Gem.dir,
      "gem_path" => Gem.path,
      "gem_name" => gem_spec.name,
      "gem_version" => gem_spec.version.to_s,
      "gem_root" => File.realpath(gem_spec.full_gem_path),
      "gem_executable" => File.realpath(Gem.bin_path("fastlane", "fastlane")),
      "library_version" => Fastlane::VERSION.to_s,
      "sources" => source_evidence
    }
  end

  def validate!(evidence)
    cli_version = Gem::Version.new(evidence.fetch("cli_version"))
    gem_spec = Gem.loaded_specs.fetch("fastlane")
    gem_root = File.realpath(gem_spec.full_gem_path)
    current_sources = source_evidence

    raise "resolved Fastlane #{cli_version} is below #{MINIMUM_VERSION}" if cli_version < MINIMUM_VERSION
    raise "resolved gem identity is not fastlane" unless evidence.fetch("gem_name") == "fastlane"
    raise "CLI and gem versions disagree" unless evidence.fetch("gem_version") == cli_version.to_s
    raise "CLI and loaded library versions disagree" unless evidence.fetch("library_version") == cli_version.to_s
    raise "loaded gem version disagrees" unless gem_spec.version == cli_version
    raise "loaded gem root disagrees" unless evidence.fetch("gem_root") == gem_root
    raise "selected Ruby disagrees" unless evidence.fetch("ruby") == File.realpath(RbConfig.ruby)
    raise "selected GEM_HOME disagrees" unless evidence.fetch("gem_home") == Gem.dir
    raise "selected GEM_PATH disagrees" unless evidence.fetch("gem_path") == Gem.path
    unless evidence.fetch("command") == resolve_path_command("fastlane")
      raise "unchanged PATH now resolves a different fastlane command"
    end
    raise "loaded source identity disagrees" unless evidence.fetch("sources") == current_sources

    current_sources.merge("gem_executable" => evidence.fetch("gem_executable")).each do |identity, sources|
      Array(sources).each do |source|
        raise "#{identity} source is unavailable" unless source

        real_source = File.realpath(source)
        unless real_source.start_with?("#{gem_root}#{File::SEPARATOR}")
          raise "#{identity} escaped the resolved Fastlane gem: #{real_source}"
        end
      end
    end

    puts "Fastlane toolchain coherent: version=#{cli_version} " \
         "sources=#{current_sources.keys.join(",")}"
    {
      "version" => cli_version,
      "gem_spec" => gem_spec,
      "gem_root" => gem_root,
      "sources" => current_sources
    }
  rescue ArgumentError => error
    raise "resolved Fastlane version is invalid: #{error.message}"
  end

  def schedule_probe
    at_exit do
      begin
        require "fastlane"
        require "sigh"
        require "sigh/manager"
        Fastlane.load_actions
        puts "#{PROBE_MARKER}#{JSON.generate(probe_evidence)}"
      rescue Exception => error # rubocop:disable Lint/RescueException
        puts "#{PROBE_MARKER}#{JSON.generate(
          "ok" => false,
          "error_class" => error.class.name,
          "error_message" => error.message
        )}"
      ensure
        $stdout.flush
      end
    end
  end

  def cli_version(command)
    stdout, stderr, status = Open3.capture3(command, "--version")
    raise "resolved fastlane command failed: #{stderr.strip}" unless status.success?

    versions = "#{stdout}\n#{stderr}".scan(/^fastlane ([^\s]+)\s*$/).flatten.uniq
    raise "resolved fastlane command reported incoherent versions: #{versions.inspect}" unless versions.one?

    Gem::Version.new(versions.first)
  rescue ArgumentError => error
    raise "resolved fastlane command reported an invalid version: #{error.message}"
  end

  def selected_evidence
    command = resolve_path_command("fastlane")
    version = cli_version(command)
    probe_rubyopt = [ENV["RUBYOPT"], "-r#{File.realpath(__FILE__)}"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(
      { PROBE_ENV => "1", "RUBYOPT" => probe_rubyopt },
      command,
      "--version"
    )
    raise "resolved fastlane toolchain probe failed: #{stderr.strip}" unless status.success?

    probe_lines = stdout.lines.grep(/^#{Regexp.escape(PROBE_MARKER)}/)
    raise "resolved fastlane toolchain emitted #{probe_lines.length} probe records" unless probe_lines.one?

    evidence = JSON.parse(probe_lines.first.delete_prefix(PROBE_MARKER))
    unless evidence["ok"]
      raise "resolved fastlane toolchain could not load: " \
            "#{evidence.fetch("error_class")}: #{evidence.fetch("error_message")}"
    end

    evidence.merge("command" => command, "cli_version" => version.to_s)
  end

  def bootstrap!
    evidence = selected_evidence
    encoded_evidence = Base64.strict_encode64(JSON.generate(evidence))
    exec(
      {
        BOOTSTRAP_ENV => "1",
        EVIDENCE_ENV => encoded_evidence,
        "GEM_HOME" => evidence.fetch("gem_home"),
        "GEM_PATH" => evidence.fetch("gem_path").join(File::PATH_SEPARATOR)
      },
      evidence.fetch("ruby"),
      File.realpath(__FILE__)
    )
  end
end

if ENV[FastlaneToolchain::PROBE_ENV] == "1"
  if File.realpath($PROGRAM_NAME) == File.realpath(__FILE__)
    raise "#{FastlaneToolchain::PROBE_ENV} is reserved for the internal Fastlane probe"
  end

  FastlaneToolchain.schedule_probe
else
  FastlaneToolchain.bootstrap! unless ENV[FastlaneToolchain::BOOTSTRAP_ENV] == "1"

module FixtureTest
  class AssertionFailure < StandardError; end

  class Case
    attr_reader :assertions

    def initialize
      @assertions = 0
    end

    def assert(value, message = "expected a truthy value")
      @assertions += 1
      raise AssertionFailure, message unless value

      value
    end

    def refute(value, message = "expected a falsey value")
      assert(!value, message)
    end

    def assert_equal(expected, actual, message = nil)
      assert(expected == actual, message || "expected #{actual.inspect} to equal #{expected.inspect}")
    end

    def assert_includes(collection, value, message = nil)
      assert(collection.include?(value), message || "expected #{collection.inspect} to include #{value.inspect}")
    end

    def refute_includes(collection, value, message = nil)
      refute(collection.include?(value), message || "expected #{collection.inspect} not to include #{value.inspect}")
    end

    def assert_empty(value, message = nil)
      assert(value.empty?, message || "expected #{value.inspect} to be empty")
    end

    def assert_nil(value, message = nil)
      assert(value.nil?, message || "expected #{value.inspect} to be nil")
    end

    def refute_nil(value, message = nil)
      refute(value.nil?, message || "expected a non-nil value")
    end

    def assert_operator(left, operator, right, message = nil)
      assert(left.public_send(operator, right),
             message || "expected #{left.inspect} to be #{operator} #{right.inspect}")
    end

    def assert_raises(*error_classes)
      @assertions += 1
      yield
    rescue *error_classes => error
      error
    else
      raise AssertionFailure, "expected #{error_classes.map(&:name).join(", ")} to be raised"
    end
  end

  module_function

  def run(test_class)
    failures = []
    assertions = 0
    tests = test_class.public_instance_methods(false)
                      .grep(/^test_/)
                      .sort

    tests.each do |test_name|
      test = test_class.new
      begin
        test.send(:setup) if test.respond_to?(:setup, true)
        test.public_send(test_name)
        print "."
      rescue StandardError => error
        failures << [test_name, error]
        print "F"
      ensure
        test.send(:teardown) if test.respond_to?(:teardown, true)
        assertions += test.assertions
      end
    end

    puts
    failures.each_with_index do |(test_name, error), index|
      puts "#{index + 1}) #{test_name}: #{error.class}: #{error.message}"
      puts Array(error.backtrace).first(5).join("\n")
    end
    puts "#{tests.length} runs, #{assertions} assertions, #{failures.length} failures"
    exit 1 unless failures.empty?
  end
end

TOOLCHAIN_EVIDENCE = JSON.parse(
  Base64.strict_decode64(ENV.fetch(FastlaneToolchain::EVIDENCE_ENV))
).freeze
gem "fastlane", "= #{TOOLCHAIN_EVIDENCE.fetch("gem_version")}"
require "fastlane"
require "sigh"
require "sigh/manager"

Fastlane.load_actions

TOOLCHAIN_SUMMARY = FastlaneToolchain.validate!(TOOLCHAIN_EVIDENCE).freeze

ROOT = File.expand_path("../..", __dir__)

class UploadReached < StandardError; end

class TestFlightFixtureLane < Fastlane::FastFile
  def initialize
    super(File.join(ROOT, "fastlane/Fastfile"))
  end

  def run
    runner.execute(:beta, :ios)
  end
end

class TestFlightPackagingTests < FixtureTest::Case
  APP_IDENTIFIER = "com.leepepe.vitalstride"
  WIDGET_IDENTIFIER = "com.leepepe.vitalstride.widgets"
  FABRICATED_APP_KEY = "sigh_#{APP_IDENTIFIER}_appstore_profile-name"
  FABRICATED_WIDGET_KEY = "sigh_#{WIDGET_IDENTIFIER}_appstore_profile-name"

  def setup
    @original_sigh_start = Sigh::Manager.method(:start)
    @original_lane_context = Fastlane::Actions.lane_context.dup
    @original_environment = tracked_environment.to_h { |key| [key, ENV[key]] }
    @original_action_runs = external_action_classes.to_h do |action|
      [action, action.method(:run)]
    end

    Fastlane::Actions.lane_context.clear
    tracked_environment.each { |key| ENV.delete(key) }
    ENV["ASC_KEY_ID"] = "fixture-key-id"
    ENV["ASC_ISSUER_ID"] = "fixture-issuer-id"
    ENV["ASC_KEY_P8_BASE64"] = "fixture-key"
    ENV["GLITCHTIP_DSN"] = ""
    stub_external_actions
  end

  def teardown
    Sigh::Manager.define_singleton_method(:start, @original_sigh_start)
    @original_action_runs.each do |action, implementation|
      action.define_singleton_method(:run, implementation)
    end
    Fastlane::Actions.lane_context.clear
    Fastlane::Actions.lane_context.merge!(@original_lane_context)
    @original_environment.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def test_uses_real_fastlane_action_and_expected_version
    expected_version = Gem::Version.new(TOOLCHAIN_EVIDENCE.fetch("cli_version"))
    gem_spec = TOOLCHAIN_SUMMARY.fetch("gem_spec")
    gem_root = TOOLCHAIN_SUMMARY.fetch("gem_root")

    assert_operator expected_version, :>=, FastlaneToolchain::MINIMUM_VERSION
    assert_equal "fastlane", TOOLCHAIN_EVIDENCE.fetch("gem_name")
    assert_equal expected_version.to_s, TOOLCHAIN_EVIDENCE.fetch("gem_version")
    assert_equal expected_version.to_s, TOOLCHAIN_EVIDENCE.fetch("library_version")
    assert_equal expected_version, gem_spec.version
    assert_equal TOOLCHAIN_EVIDENCE.fetch("gem_root"), gem_root
    assert_equal TOOLCHAIN_EVIDENCE.fetch("ruby"), File.realpath(RbConfig.ruby)
    assert_equal TOOLCHAIN_EVIDENCE.fetch("gem_home"), Gem.dir
    assert_equal TOOLCHAIN_EVIDENCE.fetch("gem_path"), Gem.path
    assert_equal TOOLCHAIN_EVIDENCE.fetch("command"),
                 FastlaneToolchain.resolve_path_command("fastlane")

    current_sources = TOOLCHAIN_SUMMARY.fetch("sources")
    assert_equal TOOLCHAIN_EVIDENCE.fetch("sources"), current_sources
    current_sources.merge(
      "gem_executable" => TOOLCHAIN_EVIDENCE.fetch("gem_executable")
    ).each do |identity, sources|
      Array(sources).each do |source|
        refute_nil source, "#{identity} source must be available"
        real_source = File.realpath(source)
        assert real_source.start_with?("#{gem_root}#{File::SEPARATOR}"),
               "#{identity} escaped the resolved Fastlane gem: #{real_source}"
      end
    end

  end

  def test_production_sources_never_read_fabricated_profile_name_keys
    production_files = Dir.glob("{fastlane,scripts}/**/*", base: ROOT).filter_map do |relative_path|
      next if relative_path == "scripts/tests/test_testflight_packaging.rb"

      absolute_path = File.join(ROOT, relative_path)
      relative_path if File.file?(absolute_path)
    end
    fabricated_read = /
      ENV
      (?:
        \s*\[\s*["']sigh_[^"']+_profile-name["']\s*\] |
        \.fetch\(\s*["']sigh_[^"']+_profile-name["']
      )
    /x
    offenders = production_files.select do |relative_path|
      content = File.binread(File.join(ROOT, relative_path))
      next false if content.include?("\0")

      content.force_encoding(Encoding::UTF_8)
             .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
             .match?(fabricated_read)
    end

    assert_empty offenders
  end

  def test_captures_distinct_current_call_names_for_archive_and_export
    requests = stub_profile_results(
      ["VitalStride App Store 2026 (App)", "app-uuid"],
      ["VitalStride Widgets Store 2026 (Widget)", "widget-uuid"]
    )
    seed_stale_profile_outputs

    lane = TestFlightFixtureLane.new
    assert_raises(UploadReached) { lane.run }

    assert_equal [APP_IDENTIFIER, WIDGET_IDENTIFIER], requests.map { |request| request[:app_identifier] }
    requests.each do |request|
      assert_equal true, request[:force]
      assert_equal false, request[:skip_install]
    end

    assert_includes @build_options[:xcargs],
                    "VITALSTRIDE_APP_PROFILE_SPECIFIER=VitalStride\\ App\\ Store\\ 2026\\ \\(App\\)"
    assert_includes @build_options[:xcargs],
                    "VITALSTRIDE_WIDGET_PROFILE_SPECIFIER=VitalStride\\ Widgets\\ Store\\ 2026\\ \\(Widget\\)"
    assert_equal "VitalStride App Store 2026 (App)",
                 @build_options.dig(:export_options, :provisioningProfiles, APP_IDENTIFIER)
    assert_equal "VitalStride Widgets Store 2026 (Widget)",
                 @build_options.dig(:export_options, :provisioningProfiles, WIDGET_IDENTIFIER)
    refute_includes @build_options[:xcargs], "app-uuid"
    refute_includes @build_options[:xcargs], "widget-uuid"
    refute_includes @build_options[:xcargs], "stale"
  end

  def test_missing_app_name_rejects_stale_sources_and_fabricated_keys
    requests = stub_profile_results([nil, "app-uuid"])
    seed_stale_profile_outputs

    lane = TestFlightFixtureLane.new
    error = assert_raises(FastlaneCore::Interface::FastlaneError) { lane.run }

    assert_equal "Missing current-run app profile name for VITALSTRIDE_APP_PROFILE_SPECIFIER",
                 error.message
    assert_equal [APP_IDENTIFIER], requests.map { |request| request[:app_identifier] }
    assert_nil @build_options
    assert_nil @upload_options
  end

  def test_missing_widget_name_rejects_app_reuse_and_stale_sources
    requests = stub_profile_results(
      ["Current App Profile", "app-uuid"],
      [nil, "widget-uuid"]
    )
    seed_stale_profile_outputs

    lane = TestFlightFixtureLane.new
    error = assert_raises(FastlaneCore::Interface::FastlaneError) { lane.run }

    assert_equal "Missing current-run widget profile name for VITALSTRIDE_WIDGET_PROFILE_SPECIFIER",
                 error.message
    assert_equal [APP_IDENTIFIER, WIDGET_IDENTIFIER], requests.map { |request| request[:app_identifier] }
    assert_nil @build_options
    assert_nil @upload_options
  end

  def test_blank_or_equal_current_names_fail_closed
    blank_lane = TestFlightFixtureLane.new
    stub_profile_results(["Current App Profile", "app-uuid"], ["   ", "widget-uuid"])
    assert_raises(FastlaneCore::Interface::FastlaneError) { blank_lane.run }
    assert_nil @build_options

    equal_lane = TestFlightFixtureLane.new
    stub_profile_results(["Shared Profile", "app-uuid"], ["Shared Profile", "widget-uuid"])
    assert_raises(FastlaneCore::Interface::FastlaneError) { equal_lane.run }
    assert_nil @build_options
  end

  private

  def tracked_environment
    [
      "SIGH_NAME", "SIGH_UUID", "SIGH_UDID",
      FABRICATED_APP_KEY, FABRICATED_WIDGET_KEY,
      "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8_BASE64", "GLITCHTIP_DSN"
    ]
  end

  def external_action_classes
    [
      Fastlane::Actions::AppStoreConnectApiKeyAction,
      Fastlane::Actions::ShAction,
      Fastlane::Actions::LatestTestflightBuildNumberAction,
      Fastlane::Actions::BuildAppAction,
      Fastlane::Actions::UploadToTestflightAction
    ]
  end

  def stub_external_actions
    test = self
    Fastlane::Actions::AppStoreConnectApiKeyAction.define_singleton_method(:run) do |_|
      { key_id: "fixture", issuer_id: "fixture", key: "fixture" }
    end
    Fastlane::Actions::ShAction.define_singleton_method(:run) { |_| nil }
    Fastlane::Actions::LatestTestflightBuildNumberAction.define_singleton_method(:run) { |_| 40 }
    Fastlane::Actions::BuildAppAction.define_singleton_method(:run) do |values|
      test.instance_variable_set(:@build_options, values.values)
    end
    Fastlane::Actions::UploadToTestflightAction.define_singleton_method(:run) do |values|
      test.instance_variable_set(:@upload_options, values.values)
      raise UploadReached
    end
  end

  def seed_stale_profile_outputs
    ENV["SIGH_NAME"] = "stale environment profile"
    ENV[FABRICATED_APP_KEY] = "stale fabricated app profile"
    ENV[FABRICATED_WIDGET_KEY] = "stale fabricated widget profile"
    Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SIGH_NAME] =
      "stale lane-context profile"
  end

  def stub_profile_results(*results)
    requests = []
    Sigh::Manager.define_singleton_method(:start) do
      requests << {
        app_identifier: Sigh.config[:app_identifier],
        force: Sigh.config[:force],
        skip_install: Sigh.config[:skip_install]
      }
      name, uuid = results.fetch(requests.length - 1)
      ENV["SIGH_NAME"] = name unless name.nil?
      ENV["SIGH_UUID"] = uuid
      "fixture.mobileprovision"
    end
    requests
  end

  FixtureTest.run(TestFlightPackagingTests)
  end

end
