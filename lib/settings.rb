# frozen_string_literal: true

require 'json'
require 'fileutils'

# Settings holds the same keys as upstream's org.gnome.Contacts GSettings
# schema (src/org.gnome.Contacts.gschema.xml).
#
# Upstream uses GSettings, which needs a compiled schema installed into the
# system's glib-2.0/schemas directory. Requiring an install step to run the
# app from a checkout is worse than the alternative, so the same keys, defaults
# and semantics are backed by a small JSON file under XDG_CONFIG_HOME instead.
#
class Settings
  DEFAULTS = {
    'did-initial-setup' => false,
    'sort-on-surname'   => false,
    'window-width'      => 800,
    'window-height'     => 600,
    'window-maximized'  => false,
    'window-fullscreen' => false,
  }.freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
  end

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = value
    write
    value
  end

  def location = @path

  # Named accessors for the keys the app reads most, so callers do not repeat
  # the string keys.
  DEFAULTS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    if DEFAULTS[key] == false
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  # Restores the window geometry recorded by the previous run.
  def apply_to(window)
    window.set_default_size(self['window-width'], self['window-height'])
    if self['window-maximized']
      window.maximize
    end
    if self['window-fullscreen']
      window.fullscreen
    end
  end

  # Records the window geometry, skipping the size while maximized or
  # fullscreen so the restored size is the one the user actually chose.
  def remember(window)
    self['window-maximized'] = window.maximized?
    self['window-fullscreen'] = window.fullscreen?

    (window.maximized? || window.fullscreen?).then do |filling_the_screen|
      unless filling_the_screen
        @values['window-width'] = window.default_width
        @values['window-height'] = window.default_height
        write
      end
    end
  end

  private

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-contacts',
        'settings.json',
      )
    end

    def read
      File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
