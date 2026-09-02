# frozen_string_literal: true

require_relative 'test_helper'
require 'main'
require 'json_backend'

# End-to-end tests that build the real widget tree and drive it through the
# window's GActions, the way a user's clicks and shortcuts would.
#
# GTK needs a display and a running main loop, so each test body is queued as
# an idle callback and the loop is torn down once it returns. Skipped
# automatically when no display is available (CI without an X or Wayland
# session).
class TestApp < Minitest::Test
  include TempData

  DISPLAY_AVAILABLE = !ENV['DISPLAY'].to_s.empty? || !ENV['WAYLAND_DISPLAY'].to_s.empty?

  def setup
    super
    skip 'no display available' unless DISPLAY_AVAILABLE
    @backend = Backends::JsonBackend.new(path: json_path)
    # A unique, non-unique(!) application id per test: without it every test
    # would try to own the same bus name and the second onwards would become a
    # remote instance whose activate handler never fires.
    # present: false keeps the window off-screen — the widget tree is built and
    # fully driveable, but a test run does not flash a window per example.
    @app = App.new(backend: @backend, app_id: "org.gnome.ContactsRb.Test#{object_id}",
                   flags: :non_unique, present: false)
    @app.build
  end

  def teardown
    @app&.window&.destroy if @app&.instance_variable_get(:@app)
    super
  end

  attr_reader :app, :backend

  # Gtk::Widget#visible? is gtk_widget_is_visible(), which is false whenever an
  # ancestor is hidden — and these tests deliberately never map the window.
  # The widget's own visibility flag, which is what the UI code sets, is the
  # "visible" property.
  def assert_shown(widget, message = nil)
    assert widget.get_property('visible'), message || "expected #{widget.class} to be shown"
  end

  def refute_shown(widget, message = nil)
    refute widget.get_property('visible'), message || "expected #{widget.class} not to be shown"
  end

  def store = app.instance_variable_get(:@store)

  # Runs the block once, inside the application's main loop. Guards against a
  # vacuous pass: if the loop never reaches the block, the test fails rather
  # than reporting success having asserted nothing.
  def in_app
    error = nil
    ran = false
    app.app.signal_connect('activate') do
      GLib::Idle.add do
        begin
          ran = true
          yield
        rescue StandardError, Minitest::Assertion => e
          error = e
        end
        app.app.quit
        false
      end
    end
    app.app.run([])
    raise error if error

    assert ran, 'the application main loop never ran the test body'
  end

  def seed(*names)
    names.each { |name| store.add_contact(name: name, emails: [{ value: "#{name.downcase}@x.com", type: 'work' }]) }
  end

  # Regression: a Gtk::ApplicationWindow draws its own titlebar on top of the
  # Adwaita header bars, which showed up as the window having two close buttons.
  def test_the_window_has_no_titlebar_of_its_own
    in_app do
      assert_kind_of Adwaita::ApplicationWindow, app.window
      # AdwApplicationWindow substitutes an empty internal gizmo for the
      # titlebar; what must not be there is a real header bar drawing a title
      # and a close button of its own.
      refute_kind_of Gtk::HeaderBar, app.window.titlebar
    end
  end

  def test_starts_on_the_empty_state
    in_app do
      assert_equal 'empty', app.contacts_list.stack.visible_child_name
      assert_equal 'none-selected-page', app.contact_pane.stack.visible_child_name
      refute_shown app.contact_sheet_buttons
      refute_predicate app.actions_bar, :reveal_child?
    end
  end

  def test_adding_contacts_shows_the_list_sorted
    in_app do
      seed('Zoe', 'Ada')
      app.contacts_list.update_visible_page
      assert_equal 'list', app.contacts_list.stack.visible_child_name
      assert_equal %w[Ada Zoe], store.contacts.map(&:name)
    end
  end

  def test_search_switches_to_the_no_results_page
    in_app do
      seed('Ada')
      store.query = 'nobody'
      app.contacts_list.update_visible_page
      assert_equal 'no-results', app.contacts_list.stack.visible_child_name

      store.query = ''
      app.contacts_list.update_visible_page
      assert_equal 'list', app.contacts_list.stack.visible_child_name
    end
  end

  def test_selecting_a_contact_shows_the_sheet
    in_app do
      seed('Ada')
      store.select_contact(store.contacts.first)
      assert_equal 'contact-sheet-page', app.contact_pane.stack.visible_child_name
      assert_shown app.contact_sheet_buttons
      assert_predicate app.actions_bar, :reveal_child?
    end
  end

  def test_new_contact_action_opens_the_editor
    in_app do
      app.window.activate_action('new-contact', nil)
      assert_equal 'contact-editor-page', app.contact_pane.stack.visible_child_name
      assert_equal '_Add', app.done_button.label
      assert_shown app.done_button
      refute_shown app.add_button
    end
  end

  # Regression: cancelling a brand-new contact used to leave the pane on the
  # "nothing selected" page even though a contact was still selected.
  def test_cancelling_a_new_contact_returns_to_the_selected_contact
    in_app do
      seed('Ada')
      store.select_contact(store.contacts.first)
      app.window.activate_action('new-contact', nil)
      app.window.activate_action('cancel', nil)

      assert_equal 'contact-sheet-page', app.contact_pane.stack.visible_child_name
      assert_shown app.contact_sheet_buttons
    end
  end

  def test_editing_a_contact_persists_to_the_backend
    in_app do
      seed('Ada')
      store.select_contact(store.contacts.first)
      app.window.activate_action('edit-contact', nil)
      assert_equal 'contact-editor-page', app.contact_pane.stack.visible_child_name

      app.contact_pane.editor.name_row.text = 'Augusta Ada King'
      app.done_button.signal_emit('clicked')

      assert_equal 'contact-sheet-page', app.contact_pane.stack.visible_child_name
      assert_equal 'Augusta Ada King', store.contacts.first.name
      assert_equal 'Augusta Ada King', backend.load.first[:name]
    end
  end

  def test_creating_a_contact_through_the_editor
    in_app do
      app.window.activate_action('new-contact', nil)
      app.contact_pane.editor.name_row.text = 'Grace Hopper'
      app.done_button.signal_emit('clicked')

      assert_equal 1, store.n_contacts
      assert_equal 'Grace Hopper', store.contacts.first.name
      assert_equal 'Grace Hopper', backend.load.first[:name]
    end
  end

  def test_delete_then_undo
    in_app do
      seed('Ada')
      store.select_contact(store.contacts.first)
      app.window.activate_action('delete-contact', nil)
      assert_equal 0, store.n_contacts
      assert_empty backend.load

      app.send(:undo_delete)
      assert_equal 1, store.n_contacts
      assert_equal 1, backend.load.length
    end
  end

  def test_favourite_actions_reorder_the_list_and_update_the_toolbar
    in_app do
      seed('Ada', 'Zoe')
      store.select_contact(store.contacts.last)
      app.window.activate_action('mark-favorite', nil)

      assert_equal %w[Zoe Ada], store.contacts.map(&:name)
      assert_equal 'win.unmark-favorite', app.favorite_button.action_name

      app.window.activate_action('unmark-favorite', nil)
      assert_equal %w[Ada Zoe], store.contacts.map(&:name)
      assert_equal 'win.mark-favorite', app.favorite_button.action_name
    end
  end

  def test_export_then_import_round_trips_through_a_file
    in_app do
      seed('Ada', 'Grace')
      File.join(tmpdir, 'out.vcf').then do |path|
        app.send(:export_to_file, Gio::File.new_for_path(path))
        assert_equal 2, File.read(path).scan('BEGIN:VCARD').length

        # Same UIDs, so importing our own export changes nothing.
        app.send(:import_file, Gio::File.new_for_path(path))
        assert_equal 2, store.n_contacts

        File.write(File.join(tmpdir, 'new.vcf'), "BEGIN:VCARD\nVERSION:4.0\nFN:Alan Turing\nEND:VCARD\n")
        app.send(:import_file, Gio::File.new_for_path(File.join(tmpdir, 'new.vcf')))
        assert_equal 3, store.n_contacts
        assert_includes store.contacts.map(&:name), 'Alan Turing'
      end
    end
  end

  def test_search_action_reveals_the_search_bar
    in_app do
      app.window.activate_action('search', nil)
      assert_predicate app.search_bar, :search_mode?
      assert_predicate app.search_button, :active?
    end
  end

  def test_accelerators_are_registered
    in_app do
      assert_equal ['<Control>n'], app.app.get_accels_for_action('win.new-contact')
      assert_equal ['<Control>e'], app.app.get_accels_for_action('win.edit-contact')
      assert_equal ['Delete'], app.app.get_accels_for_action('win.delete-contact')
      assert_equal ['<Control>f'], app.app.get_accels_for_action('win.search')
      assert_equal ['Escape'], app.app.get_accels_for_action('win.cancel')
      assert_equal ['<Control>i'], app.app.get_accels_for_action('app.import')
      # GTK normalises modifier order when it parses an accelerator.
      assert_equal ['<Shift><Control>e'], app.app.get_accels_for_action('app.export-all')
      assert_equal ['<Control>q', '<Control>w'], app.app.get_accels_for_action('app.quit')
    end
  end

  # Every field group is present even when the contact has nothing in it, so
  # the sheet does not reflow as the selection moves.
  def test_the_sheet_shows_every_group_for_a_bare_contact
    in_app do
      store.add_contact(name: 'Bare')
      store.select_contact(store.contacts.first)
      app.contact_pane.sheet.then do |sheet|
        %i[roles_group emails_group phones_group urls_group
           addresses_group birthday_group nickname_group notes_group].each do |group|
          refute_nil sheet.public_send(group), "#{group} should exist"
        end
      end
    end
  end
end
