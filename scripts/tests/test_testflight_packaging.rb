# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rubygems"

gem "fastlane", "= 2.238.0"
require "fastlane"
require "sigh"
require "sigh/manager"

Fastlane.load_actions

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

class TestFlightPackagingTests < Minitest::Test
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
    expected_version = Gem::Version.new("2.238.0")
    stdout, stderr, status = Open3.capture3("fastlane", "_2.238.0_", "--version")

    assert status.success?, stderr
    assert_match(/fastlane 2\.238\.0\b/, stdout)
    assert_equal expected_version, Gem.loaded_specs.fetch("fastlane").version

    action_source, = Fastlane::Actions::GetProvisioningProfileAction.method(:run).source_location
    manager_source, = Sigh::Manager.method(:start).source_location
    assert_includes action_source, "/fastlane-2.238.0/"
    assert_includes manager_source, "/fastlane-2.238.0/"
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

    assert_includes error.message, "app profile name"
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

    assert_includes error.message, "widget profile name"
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
      name.nil? ? ENV.delete("SIGH_NAME") : ENV["SIGH_NAME"] = name
      ENV["SIGH_UUID"] = uuid
      "fixture.mobileprovision"
    end
    requests
  end
end
