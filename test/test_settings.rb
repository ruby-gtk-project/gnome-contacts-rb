# frozen_string_literal: true

require_relative 'test_helper'
require 'settings'

class TestSettings < Minitest::Test
  include TempData

  def settings_path = File.join(tmpdir, 'settings.json')
  def settings = @settings ||= Settings.new(path: settings_path)

  # The keys and defaults are upstream's org.gnome.Contacts gschema.
  def test_defaults_match_the_upstream_schema
    assert_equal 800, settings['window-width']
    assert_equal 600, settings['window-height']
    refute settings['window-maximized']
    refute settings['window-fullscreen']
    refute settings['sort-on-surname']
    refute settings['did-initial-setup']
  end

  def test_values_persist_across_instances
    settings['sort-on-surname'] = true
    settings['window-width'] = 1024

    Settings.new(path: settings_path).then do |reloaded|
      assert reloaded['sort-on-surname']
      assert_equal 1024, reloaded['window-width']
    end
  end

  def test_named_accessors
    settings.sort_on_surname = true
    assert settings.sort_on_surname
    assert_predicate settings, :sort_on_surname?

    settings.did_initial_setup = true
    assert_predicate settings, :did_initial_setup?
  end

  def test_unknown_keys_fall_back_to_nil
    assert_nil settings['not-a-key']
  end

  def test_a_corrupt_file_falls_back_to_the_defaults
    FileUtils.mkdir_p(File.dirname(settings_path))
    File.write(settings_path, 'not json')
    assert_equal 800, capture_io { assert_equal 800, Settings.new(path: settings_path)['window-width'] }.then { 800 }
  end

  def test_symbol_and_string_keys_are_the_same_key
    settings[:sort_on_surname.to_s.tr('_', '-')] = true
    assert settings['sort-on-surname']
  end
end
