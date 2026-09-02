# frozen_string_literal: true

require_relative 'test_helper'
require 'main'
require 'json_backend'
require 'vcard'
require 'settings'
require 'qr_code_dialog'
require 'preferences_dialog'
require 'shortcuts_dialog'
require 'import_dialog'
require 'setup_window'
require 'vcard_backend'

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
    unless DISPLAY_AVAILABLE
      skip 'no display available'
    end
    @backend = Backends::JsonBackend.new(path: json_path)
    # A unique, non-unique(!) application id per test: without it every test
    # would try to own the same bus name and the second onwards would become a
    # remote instance whose activate handler never fires.
    # present: false keeps the window off-screen — the widget tree is built and
    # fully driveable, but a test run does not flash a window per example.
    # search_provider: false because every instance would otherwise export the
    # same D-Bus object path; the provider has its own test.
    @app = App.new(
      backend:         @backend,
      app_id:          "org.gnome.ContactsRb.Test#{object_id}",
      flags:           :non_unique,
      present:         false,
      search_provider: false,
      settings:        Settings.new(path: File.join(@tmpdir, 'settings.json')),
    )
    @app.build
  end

  def teardown
    if @app&.instance_variable_get(:@app)
      @app&.window&.destroy
    end
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

  # Lets GTK lay out after a change that rebuilds the rows: a fresh factory
  # leaves the list view with no realised children until the next turn of the
  # loop, so anything reading row widgets has to wait one out.
  # GTK4 has no Gtk.main_iteration; pumping the default main context is the
  # equivalent, and it is enough to let a rebuilt list view realise its rows.
  def settle
    GLib::MainContext.default.then do |context|
      64.times do
        unless context.pending?
          break
        end

        context.iteration(false)
      end
    end
  end

  # The tick state of each realised row.
  def rendered_checkboxes
    [].tap do |ticks|
      row = app.contacts_list.list_view.first_child
      while row
        ticks << row.first_child.first_child.active?
        row = row.next_sibling
      end
    end
  end

  # Walks the realised list rows and reads the primary label out of each, so a
  # test can assert on what the sidebar actually shows rather than on the model.
  def rendered_row_labels
    [].tap do |labels|
      row = app.contacts_list.list_view.first_child
      while row
        row.first_child.then do |box|
          box&.first_child&.next_sibling&.next_sibling.then do |label_box|
            if label_box.respond_to?(:first_child)
              labels << label_box.first_child.label
            end
          end
        end
        row = row.next_sibling
      end
    end
  end

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
    if error
      raise error
    end

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

      app.window.activate_action('undo-operation', nil)
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
        app.send(:write_export, Gio::File.new_for_path(path), store.contacts)
        assert_equal 2, File.read(path).scan('BEGIN:VCARD').length

        # Same UIDs, so importing our own export changes nothing.
        app.send(:import_parsed, VCard.parse_all(File.read(path)))
        assert_equal 2, store.n_contacts

        File.write(File.join(tmpdir, 'new.vcf'), "BEGIN:VCARD\nVERSION:4.0\nFN:Alan Turing\nEND:VCARD\n")
        app.send(:import_parsed, VCard.parse_all(File.read(File.join(tmpdir, 'new.vcf'))))
        assert_equal 3, store.n_contacts
        assert_includes store.contacts.map(&:name), 'Alan Turing'
      end
    end
  end

  def test_search_action_reveals_the_search_bar
    in_app do
      app.window.activate_action('focus-search', nil)
      assert_predicate app.search_bar, :search_mode?
      assert_predicate app.search_button, :active?
    end
  end

  def test_accelerators_are_registered
    in_app do
      assert_equal ['<Control>n'], app.app.get_accels_for_action('win.new-contact')
      assert_equal ['<Control>e'], app.app.get_accels_for_action('win.edit-contact')
      assert_equal ['Delete'], app.app.get_accels_for_action('win.delete-contact')
      assert_equal ['<Control>f'], app.app.get_accels_for_action('win.focus-search')
      assert_equal ['Escape'], app.app.get_accels_for_action('win.cancel')
      assert_equal ['<Control>i'], app.app.get_accels_for_action('app.import')
      # GTK normalises modifier order when it parses an accelerator.
      assert_equal ['<Shift><Control>e'], app.app.get_accels_for_action('app.export-all')
      assert_equal ['<Control>q', '<Control>w'], app.app.get_accels_for_action('app.quit')
    end
  end

  # --- Selection mode -----------------------------------------------------

  def test_selection_mode_swaps_the_header_and_the_bottom_bar
    in_app do
      seed('Ada', 'Grace')
      app.window.activate_action('select-contacts', nil)

      assert_predicate app.contacts_list, :selection_mode?
      refute_shown app.left_header
      assert_shown app.selection_header
      assert_shown app.link_button
      refute_shown app.favorite_button
      assert_predicate app.actions_bar, :reveal_child?

      app.window.activate_action('cancel-selection', nil)
      refute_predicate app.contacts_list, :selection_mode?
      assert_shown app.left_header
      refute_shown app.selection_header
    end
  end

  def test_escape_leaves_selection_mode
    in_app do
      seed('Ada')
      app.window.activate_action('select-contacts', nil)
      app.window.activate_action('cancel', nil)
      refute_predicate app.contacts_list, :selection_mode?
    end
  end

  # Regression: the checkbox was set once at bind time, so marking a row later
  # highlighted it and bumped the header count while the tick stayed empty.
  def test_row_checkboxes_follow_the_marked_state
    in_app do
      seed('Ada', 'Grace')
      app.window.activate_action('select-contacts', nil)
      settle

      assert_equal [false, false], rendered_checkboxes
      store.multi_selection_model.select_item(1, false)
      assert_equal [false, true], rendered_checkboxes
      store.multi_selection_model.select_all
      assert_equal [true, true], rendered_checkboxes
    end
  end

  # Regression: sensitivity is driven by the marked count while selection mode
  # is on, and leaving it used to leave the whole bottom bar dead.
  def test_the_action_bar_comes_back_to_life_after_selection_mode
    in_app do
      seed('Ada')
      store.select_contact(store.contacts.first)
      assert_predicate app.delete_button, :sensitive?

      app.window.activate_action('select-contacts', nil)
      refute_predicate app.delete_button, :sensitive?, 'nothing marked yet'

      app.window.activate_action('cancel-selection', nil)
      assert_predicate app.delete_button, :sensitive?
      assert_predicate app.export_button, :sensitive?
      assert_predicate app.favorite_button, :sensitive?
    end
  end

  def test_marked_contacts_drive_the_bulk_action_buttons
    in_app do
      seed('Ada', 'Grace')
      app.window.activate_action('select-contacts', nil)
      assert_equal 'Select Contacts', app.selection_title.title
      refute_predicate app.link_button, :sensitive?

      store.multi_selection_model.select_item(0, false)
      assert_equal '1 Selected', app.selection_title.title
      refute_predicate app.link_button, :sensitive?, 'linking needs at least two'
      assert_predicate app.delete_button, :sensitive?

      store.multi_selection_model.select_all
      assert_equal '2 Selected', app.selection_title.title
      assert_predicate app.link_button, :sensitive?
    end
  end

  def test_delete_marked_contacts_deletes_all_of_them
    in_app do
      seed('Ada', 'Grace', 'Alan')
      app.window.activate_action('select-contacts', nil)
      store.multi_selection_model.select_all
      app.window.activate_action('delete-marked-contacts', nil)

      assert_equal 0, store.n_contacts
      refute_predicate app.contacts_list, :selection_mode?, 'deleting leaves selection mode'

      app.window.activate_action('undo-operation', nil)
      assert_equal 3, store.n_contacts
    end
  end

  def test_link_marked_contacts_merges_them
    in_app do
      store.add_contact(name: 'Ada Lovelace', emails: [{ value: 'ada@work.com', type: 'Work' }])
      store.add_contact(name: 'Ada Lovelace', phones: [{ value: '555', type: 'Mobile' }])

      app.window.activate_action('select-contacts', nil)
      store.multi_selection_model.select_all
      app.window.activate_action('link-marked-contacts', nil)

      assert_equal 1, store.n_contacts
      assert_equal ['555'], store.contacts.first.phones.map(&:value)
      assert_equal ['ada@work.com'], store.contacts.first.emails.map(&:value)

      app.window.activate_action('undo-operation', nil)
      assert_equal 2, store.n_contacts
    end
  end

  def test_unlink_reverses_the_last_link
    in_app do
      seed('Ada', 'Grace')
      app.window.activate_action('select-contacts', nil)
      store.multi_selection_model.select_all
      app.window.activate_action('link-marked-contacts', nil)
      assert_equal 1, store.n_contacts

      store.select_contact(store.contacts.first)
      app.window.activate_action('unlink-contact', nil)
      assert_equal 2, store.n_contacts
    end
  end

  # --- Sorting ------------------------------------------------------------

  def test_sort_on_surname_reorders_and_persists
    in_app do
      store.add_contact(name: 'Ada Zeta', structured_name: { given: 'Ada', family: 'Zeta' })
      store.add_contact(name: 'Zoe Alpha', structured_name: { given: 'Zoe', family: 'Alpha' })
      assert_equal ['Ada Zeta', 'Zoe Alpha'], store.contacts.map(&:name)

      app.window.activate_action('sort-on', GLib::Variant.new('surname'))
      assert_equal ['Zoe Alpha', 'Ada Zeta'], store.contacts.map(&:name)
      assert app.settings['sort-on-surname']

      app.window.activate_action('sort-on', GLib::Variant.new('first-name'))
      assert_equal ['Ada Zeta', 'Zoe Alpha'], store.contacts.map(&:name)
      refute app.settings['sort-on-surname']
    end
  end

  # Regression: reordering the same objects makes Gtk::ListView move the
  # existing rows rather than rebind them, so the labels kept showing the
  # first-name form after switching to surname order.
  def test_the_row_labels_follow_the_sort_order
    in_app do
      store.add_contact(name: 'Ada Zeta', structured_name: { given: 'Ada', family: 'Zeta' })
      store.add_contact(name: 'Zoe Alpha', structured_name: { given: 'Zoe', family: 'Alpha' })
      app.contacts_list.update_visible_page

      assert_equal ['Ada Zeta', 'Zoe Alpha'], rendered_row_labels

      app.window.activate_action('sort-on', GLib::Variant.new('surname'))
      assert_equal ['Alpha, Zoe', 'Zeta, Ada'], rendered_row_labels

      app.window.activate_action('sort-on', GLib::Variant.new('first-name'))
      assert_equal ['Ada Zeta', 'Zoe Alpha'], rendered_row_labels
    end
  end

  # --- Dialogs ------------------------------------------------------------

  def test_qr_code_dialog_renders_the_contacts_vcard
    in_app do
      seed('Ada')
      store.select_contact(store.contacts.first)
      QrCodeDialog.new(store.contacts.first).tap do |dialog|
        dialog.build
        refute_nil dialog.qr_image.paintable, 'the QR code should have rendered'
      end
    end
  end

  def test_preferences_dialog_reports_the_backend
    in_app do
      seed('Ada')
      PreferencesDialog.new(store, app.settings, ->(_) {}).tap do |dialog|
        dialog.build
        assert_equal backend.display_name, dialog.backend_row.title
        assert_equal backend.location, dialog.backend_row.subtitle
      end
    end
  end

  def test_shortcuts_dialog_builds
    in_app { refute_nil ShortcutsDialog.new.build }
  end

  def test_import_dialog_previews_before_importing
    in_app do
      File.join(tmpdir, 'in.vcf').then do |path|
        File.write(path, "BEGIN:VCARD\nVERSION:4.0\nFN:Alan Turing\nEND:VCARD\n")
        imported = nil
        ImportDialog.new([Gio::File.new_for_path(path)], ->(c) { imported = c }).tap do |dialog|
          dialog.build
          assert_predicate dialog.import_button, :sensitive?, 'a file with contacts enables Import'
          dialog.send(:confirm)
        end
        assert_equal ['Alan Turing'], imported.map { |c| c[:name] }
        assert_equal 0, store.n_contacts, 'the dialog previews; it does not import by itself'
      end
    end
  end

  def test_import_dialog_reports_a_file_with_nothing_in_it
    in_app do
      File.join(tmpdir, 'empty.vcf').then do |path|
        File.write(path, 'not a vcard at all')
        ImportDialog.new([Gio::File.new_for_path(path)], ->(_) {}).tap do |dialog|
          dialog.build
          refute_predicate dialog.import_button, :sensitive?
        end
      end
    end
  end

  # --- First-run setup ----------------------------------------------------

  # The gate is pure state, so it needs no window: setup happens when the
  # did-initial-setup key is unset and address books were offered.
  def test_setup_is_gated_on_the_did_initial_setup_setting
    Settings.new(path: File.join(tmpdir, 'setup.json')).then do |settings|
      backends = [Backends::JsonBackend.new(path: json_path)]

      App.new(settings: settings, setup_backends: backends, present: false).then do |fresh|
        assert fresh.send(:setup_needed?), 'a fresh install runs setup'
      end

      settings['did-initial-setup'] = true
      App.new(settings: settings, setup_backends: backends, present: false).then do |returning|
        refute returning.send(:setup_needed?), 'setup only happens once'
      end
    end
  end

  def test_setup_is_skipped_when_no_address_books_are_offered
    in_app { refute app.send(:setup_needed?) }
  end

  # The window itself is built against the application the test already has,
  # rather than running a second one, which GTK does not survive in-process.
  def test_setup_window_lists_the_address_books_and_reports_the_choice
    in_app do
      [Backends::JsonBackend.new(path: json_path),
       Backends::VCardBackend.new(path: vcard_dir)
].then do |backends|
        chosen = nil
        SetupWindow.new(app.app, backends, ->(backend) { chosen = backend }).tap do |setup|
          setup.build
          assert_equal 'Contacts Setup', setup.window.title
          assert_predicate setup.done_button, :sensitive?, 'the first book is preselected'

          setup.send(:finish)
          assert_same backends.first, chosen
          # Deliberately not destroyed: tearing down a window that was never
          # presented trips a Gdk assertion and takes the process with it.
        end
      end
    end
  end

  def test_finishing_setup_records_the_choice
    Settings.new(path: File.join(tmpdir, 'setup2.json')).then do |settings|
      Backends::VCardBackend.new(path: vcard_dir).then do |chosen|
        App.new(settings: settings, setup_backends: [chosen], present: false).tap do |fresh|
          fresh.send(:finish_setup, chosen)
          assert settings['did-initial-setup']
          assert_same chosen, fresh.instance_variable_get(:@backend)
        end
      end
    end
  end

  # --- Window geometry ----------------------------------------------------

  def test_window_geometry_is_restored_and_remembered
    in_app do
      assert_equal 800, app.window.default_width
      assert_equal 600, app.window.default_height

      app.window.set_default_size(1024, 720)
      app.settings.remember(app.window)
      assert_equal 1024, app.settings['window-width']
      assert_equal 720, app.settings['window-height']
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
           addresses_group birthday_group nickname_group notes_group
].each do |group|
          refute_nil sheet.public_send(group), "#{group} should exist"
        end
      end
    end
  end
end
