# frozen_string_literal: true

# Drives the real first-run setup flow end to end: App started with a
# non-empty setup_backends list and no prior "did-initial-setup" setting
# shows SetupWindow instead of the main window, picking an address book and
# clicking Done records the choice and opens the main window afterward.
#
# Ported-flow equivalent of upstream's contacts-setup-window.vala wiring in
# contacts-app.vala: `vala_app.activate` opens the setup window first when
# no address book has been chosen yet.
#
#   nix develop --command xvfb-run -a ruby test/drive_setup_flow.rb
#
# This is the live-click path component-parity.md flagged as never reached:
# the main drive script always passes zero setup_backends, so SetupWindow is
# legitimately unreachable from that run, and test_app.rb only constructs
# SetupWindow directly, off the real App#activate wiring.

require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# See drive_main_window.rb for why GC is disabled here: GLib2's closure
# marshaling calls back into Ruby from a GObject C callback, and a GC sweep
# starting mid-callback aborts the VM. Same short-lived, single-purpose
# process, so disabling GC changes nothing about what the checks observe.
GC.disable

Dir.mktmpdir('contacts-setup-drive').tap do |dir|
  ENV['XDG_CONFIG_HOME'] = File.join(dir, 'config')
  ENV['XDG_DATA_HOME'] = File.join(dir, 'data')
end

require 'main'
require 'json_backend'
require 'vcard_backend'
require 'settings'
require_relative 'gtk_driver'

DIR = Dir.mktmpdir('contacts-setup-drive-store')
JSON_BACKEND = Backends::JsonBackend.new(path: File.join(DIR, 'contacts.json'))
VCARD_BACKEND = Backends::VCardBackend.new(path: Dir.mktmpdir('contacts-setup-drive-vcard'))
# A fresh Settings with did-initial-setup still false, so App#setup_needed?
# is true for the very first activation, exactly like a real first run.
SETTINGS = Settings.new(path: File.join(DIR, 'settings.json'))

App.new(
  settings:        SETTINGS,
  setup_backends:  [JSON_BACKEND, VCARD_BACKEND],
  app_id:          'org.gnome.ContactsRb.DriveSetup',
  flags:           :non_unique,
  search_provider: false,
).then do |app|
  GtkDriver.drive(app, shots: 'tmp/shots') do |d, _|
    d.window { app.instance_variable_get(:@setup_window)&.send(:window) || app.window }

    d.step('activating the app with no prior setup shows the setup window, not the main window') do
      d.check('setup is needed on a fresh settings file') { !SETTINGS['did-initial-setup'] }
      setup_window = app.instance_variable_get(:@setup_window)
      d.check('a SetupWindow was built') { !setup_window.nil? }
      d.check('the main window was never built') { app.instance_variable_get(:@store).nil? }
      d.shot('20-setup-window')
    end

    d.step('the setup window lists both candidate address books') do
      setup_window = app.instance_variable_get(:@setup_window)
      accounts_list = setup_window.send(:accounts_list)
      d.check('both backends appear as rows') { accounts_list.rows.size == 2 }
      d.check('the first backend is selected by default') do
        accounts_list.selected_backend.equal?(JSON_BACKEND)
      end
    end

    d.step('pick the second address book (vCard) in the setup window') do
      setup_window = app.instance_variable_get(:@setup_window)
      accounts_list = setup_window.send(:accounts_list)
      accounts_list.selected_backend = VCARD_BACKEND
    end

    d.step('the selection moved and Done became clickable') do
      setup_window = app.instance_variable_get(:@setup_window)
      accounts_list = setup_window.send(:accounts_list)
      d.check('the vCard backend is now selected') { accounts_list.selected_backend.equal?(VCARD_BACKEND) }
      d.check('the Done button is sensitive') { setup_window.send(:done_button).sensitive? }
    end

    d.step('click Done') do
      setup_window = app.instance_variable_get(:@setup_window)
      setup_window.send(:done_button).activate
    end

    # finish_setup defers reopening the main window to a GLib idle tick (see
    # lib/main.rb's comment on why), so the window only exists a tick later.
    d.step('the choice was recorded and the main window opens afterward') do
      d.check('did-initial-setup is now true') { SETTINGS['did-initial-setup'] == true }
      d.check('the setup window is gone') { app.instance_variable_get(:@setup_window).nil? }
      d.check('the main window was built') { !app.instance_variable_get(:@store).nil? }
      d.check('the chosen backend (vCard) is what the main window is using') do
        app.instance_variable_get(:@store).backend.equal?(VCARD_BACKEND)
      end
      d.shot('21-setup-done-main-window')
    end
  end
end
