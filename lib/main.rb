# frozen_string_literal: true

require 'adwaita'

require_relative 'contact'
require_relative 'contact_store'
require_relative 'contact_pane'
require_relative 'contact_list'
require_relative 'vcard'
require_relative 'settings'
require_relative 'operations'
require_relative 'qr_code_dialog'
require_relative 'preferences_dialog'
require_relative 'shortcuts_dialog'
require_relative 'import_dialog'
require_relative 'shell_search_provider'
require_relative 'setup_window'

# App is the main application class.
#
# Ported from upstream's src/contacts-app.vala, src/contacts-main-window.vala
# and data/ui/contacts-main-window.blp: a navigation split view with the
# contact list in the sidebar and the sheet/editor in the content pane, a
# selection mode for bulk actions, and an undo stack behind the toasts.
#
class App
  APP_ID = 'org.gnome.ContactsRb'
  HELP_URI = 'https://gitlab.gnome.org/GNOME/gnome-contacts'

  NORMAL   = :normal
  SHOWING  = :showing
  CREATING = :creating
  UPDATING = :updating

  # Window actions, mirroring upstream's ACTION_ENTRIES, and the accelerators
  # its shortcuts dialog advertises.
  WINDOW_ACTIONS = {
    'new-contact'             => ['<Control>n'],
    'edit-contact'            => ['<Control>e'],
    'edit-contact-save'       => ['<Control>Return'],
    'delete-contact'          => ['Delete'],
    'focus-search'            => ['<Control>f'],
    'cancel'                  => ['Escape'],
    'mark-favorite'           => [],
    'unmark-favorite'         => [],
    'select-contacts'         => [],
    'cancel-selection'        => [],
    'link-marked-contacts'    => [],
    'delete-marked-contacts'  => [],
    'export-marked-contacts'  => [],
    'export-selected-contact' => [],
    'show-contact-qr-code'    => [],
    'unlink-contact'          => [],
    'undo-operation'          => ['<Control>z'],
  }.freeze

  APP_ACTIONS = {
    'import'           => ['<Control>i'],
    'export-all'       => ['<Control><Shift>e'],
    'show-preferences' => ['<Control>comma'],
    'shortcuts'        => ['<Control>question'],
    'help'             => ['F1'],
    'about'            => [],
    'quit'             => ['<Control>q', '<Control>w'],
  }.freeze

  attr_reader :settings, :operations

  # app_id/flags are injectable so tests can register a throwaway, non-unique
  # application instead of talking to the session's real one; present: false
  # builds the whole widget tree without ever mapping the window, so a test run
  # does not flash a window onto the user's desktop for every example.
  def initialize(backend: nil, app_id: APP_ID, flags: :default_flags, present: true,
                 settings: nil, startup_query: nil, startup_contact_id: nil,
                 search_provider: true, setup_backends: nil)
    @backend = backend
    @setup_backends = setup_backends
    @app_id = app_id
    @flags = flags
    @present = present
    @settings = settings || Settings.new
    @startup_query = startup_query
    @startup_contact_id = startup_contact_id
    @search_provider_enabled = search_provider
    @operations = Operations::OperationList.new
    @state = NORMAL
    @selection_mode = false
    @rejected_suggestions = {}
  end

  def build
    app.tap do |a|
      a.signal_connect('activate') do
        if setup_needed?
          run_setup
          next
        end

        @store = ContactStore.new(backend: @backend, sort_on_surname: @settings['sort-on-surname'])
        @store.load

        window.tap do |win|
          win.content = toast_overlay

          toast_overlay.tap do |to|
            to.child = content_box

            content_box.tap do |cb|
              cb.sidebar = list_pane_page
              cb.content = contact_pane_page

              list_pane_page.tap do
                sidebar_toolbar.tap do |st|
                  st.add_top_bar(left_header)
                  st.add_top_bar(selection_header)
                  st.add_top_bar(search_bar)
                  st.content = contacts_list.build
                  st.add_bottom_bar(actions_bar)

                  left_header.tap do |hb|
                    hb.pack_start(add_button)
                    hb.pack_end(primary_menu_button)
                    hb.pack_end(search_button)
                    hb.pack_end(select_button)
                  end

                  selection_header.tap do |hb|
                    hb.show_end_title_buttons = false
                    hb.pack_end(cancel_selection_button)
                    hb.title_widget = selection_title
                  end

                  search_bar.tap do |sb|
                    sb.child = filter_entry
                    sb.connect_entry(filter_entry)
                    sb.key_capture_widget = window

                    filter_entry.signal_connect('search-changed') do
                      @store.query = filter_entry.text
                      contacts_list.update_visible_page
                    end
                  end

                  actions_bar.tap do |ab|
                    ab.child = actions_box

                    actions_box.tap do |box|
                      box.append(favorite_button)
                      box.append(link_button)
                      box.append(export_button)
                      box.append(delete_button)
                    end
                  end
                end
              end

              contact_pane_page.tap do
                content_toolbar.tap do |ct|
                  ct.add_top_bar(right_header)
                  ct.content = contact_pane.build

                  right_header.tap do |hb|
                    hb.pack_start(cancel_button)
                    hb.pack_end(done_button)
                    hb.pack_end(contact_sheet_buttons)

                    contact_sheet_buttons.tap do |csb|
                      csb.append(edit_button)
                      csb.append(contact_menu_button)
                    end
                  end
                end
              end
            end
          end

          @store.selection_model.signal_connect('notify::selected') { on_selection_changed }
          @store.multi_selection_model.signal_connect('selection-changed') { update_selection_ui }
          win.signal_connect('close-request') { @settings.remember(win); false }
        end

        setup_actions
        register_search_provider
        apply_startup_query
        update_ui_for_state
        show_window
      end
    end
  end

  def run = app.run([])

  # Memoized widget methods

  def app
    @app ||= begin
      Adwaita.init
      Gtk::Application.new(@app_id, @flags)
    end
  end

  # Adwaita::ApplicationWindow, not Gtk::ApplicationWindow: the Gtk one draws
  # its own default titlebar, which would sit above our two Adwaita header
  # bars and give the window a second close button. The Adwaita window owns no
  # titlebar of its own, and it also keeps Adwaita::Dialog inside the window
  # instead of spawning a second toplevel.
  #
  # (Adwaita::Application is still broken in the bindings, so the application
  # object above stays a Gtk::Application.)
  def window
    @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
      win.title = 'Contacts'
      win.icon_name = 'address-book-new-symbolic'
      @settings.apply_to(win)
    end
  end

  def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

  def content_box
    @content_box ||= Adwaita::NavigationSplitView.new.tap do |cb|
      cb.sidebar_width_fraction = 0.3
      cb.min_sidebar_width = 280
      cb.max_sidebar_width = 380
    end
  end

  def list_pane_page = @list_pane_page ||= Adwaita::NavigationPage.new(sidebar_toolbar, 'Contacts')
  def sidebar_toolbar = @sidebar_toolbar ||= Adwaita::ToolbarView.new
  def left_header = @left_header ||= Adwaita::HeaderBar.new

  def selection_header
    @selection_header ||= Adwaita::HeaderBar.new.tap do |hb|
      hb.visible = false
    end
  end

  def selection_title = @selection_title ||= Adwaita::WindowTitle.new('Select Contacts', '')

  def cancel_selection_button
    @cancel_selection_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Cancel'
      btn.use_underline = true
      btn.action_name = 'win.cancel-selection'
    end
  end

  def add_button
    @add_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'list-add-symbolic'
      btn.tooltip_text = 'Add New Contact (Ctrl+N)'
      btn.action_name = 'win.new-contact'
    end
  end

  def search_button
    @search_button ||= Gtk::ToggleButton.new.tap do |btn|
      btn.icon_name = 'system-search-symbolic'
      btn.tooltip_text = 'Search (Ctrl+F)'
    end
  end

  def select_button
    @select_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'selection-mode-symbolic'
      btn.tooltip_text = 'Select Contacts'
      btn.action_name = 'win.select-contacts'
    end
  end

  def primary_menu_button
    @primary_menu_button ||= Gtk::MenuButton.new.tap do |btn|
      btn.icon_name = 'open-menu-symbolic'
      btn.tooltip_text = 'Main Menu (F10)'
      btn.menu_model = primary_menu
      btn.add_css_class('flat')
    end
  end

  # The same menu upstream builds in contacts-main-window.blp.
  def primary_menu
    @primary_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(
        'List Contacts By:',
        Gio::Menu.new.tap do |section|
                section.append('_First Name', 'win.sort-on::first-name')
                section.append('_Surname', 'win.sort-on::surname')
              end,
      )

      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_Import From File…', 'app.import')
                section.append('_Export All Contacts…', 'app.export-all')
              end,
      )

      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_Preferences', 'app.show-preferences')
                section.append('_Keyboard Shortcuts', 'app.shortcuts')
                section.append('_Help', 'app.help')
                section.append('_About Contacts', 'app.about')
              end,
      )
    end
  end

  def search_bar
    @search_bar ||= Gtk::SearchBar.new.tap do |sb|
      sb.show_close_button = false
    end
  end

  def filter_entry
    @filter_entry ||= Gtk::SearchEntry.new.tap do |fe|
      fe.placeholder_text = 'Search contacts'
      fe.hexpand = true
    end
  end

  def contacts_list = @contacts_list ||= ContactList.new(@store)

  def actions_bar
    @actions_bar ||= Gtk::Revealer.new.tap do |ab|
      ab.reveal_child = false
      ab.transition_type = :slide_up
    end
  end

  def actions_box
    @actions_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.add_css_class('toolbar')
      box.homogeneous = true
      box.margin_start = 6
      box.margin_end = 6
    end
  end

  def favorite_button
    @favorite_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Favourite'
      btn.use_underline = true
      btn.action_name = 'win.mark-favorite'
    end
  end

  def link_button
    @link_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Link'
      btn.use_underline = true
      btn.visible = false
      btn.action_name = 'win.link-marked-contacts'
    end
  end

  def export_button
    @export_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Export'
      btn.use_underline = true
      btn.action_name = 'win.export-selected-contact'
    end
  end

  def delete_button
    @delete_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Delete'
      btn.use_underline = true
      btn.add_css_class('destructive-action')
      btn.action_name = 'win.delete-contact'
    end
  end

  def contact_pane_page = @contact_pane_page ||= Adwaita::NavigationPage.new(content_toolbar, 'Select a Contact')
  def content_toolbar = @content_toolbar ||= Adwaita::ToolbarView.new

  def right_header
    @right_header ||= Adwaita::HeaderBar.new.tap do |hb|
      hb.show_title = false
    end
  end

  def cancel_button
    @cancel_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Cancel'
      btn.use_underline = true
      btn.visible = false
      btn.action_name = 'win.cancel'
    end
  end

  def done_button
    @done_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Done'
      btn.use_underline = true
      btn.visible = false
      btn.add_css_class('suggested-action')
      btn.action_name = 'win.edit-contact-save'
    end
  end

  def contact_sheet_buttons
    @contact_sheet_buttons ||= Gtk::Box.new(:horizontal, 6).tap do |csb|
      csb.visible = false
    end
  end

  def edit_button
    @edit_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'document-edit-symbolic'
      btn.tooltip_text = 'Edit Contact (Ctrl+E)'
      btn.action_name = 'win.edit-contact'
    end
  end

  def contact_menu_button
    @contact_menu_button ||= Gtk::MenuButton.new.tap do |btn|
      btn.icon_name = 'view-more-symbolic'
      btn.tooltip_text = 'Contact Menu'
      btn.add_css_class('flat')
    end
  end

  def contact_pane
    @contact_pane ||= ContactPane.new(
      @store,
      method(:on_contact_saved),
      on_link:   method(:accept_suggestion),
      on_reject: method(:reject_suggestion),
    )
  end

  def about_dialog
    @about_dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_name = 'Contacts'
      about.application_icon = 'address-book-new-symbolic'
      about.developer_name = 'The Ruby GTK Project'
      about.version = '0.1.0'
      about.comments = 'A Ruby port of GNOME Contacts, built with gtk4 and libadwaita.'
      about.website = 'https://github.com/ruby-gtk-project/gnome-contacts-rb'
      about.issue_url = 'https://github.com/ruby-gtk-project/gnome-contacts-rb/issues'
      about.license_type = Gtk::License::GPL_2_0
    end
  end

  private

    def show_window
      if @present
        window.present
      end
    end

  # First run shows upstream's setup wizard instead of the main window, gated
  # on the same did-initial-setup key. Choosing an address book records the
  # choice and then opens the app proper.
    def setup_needed? = !@settings['did-initial-setup'] && !Array(@setup_backends).empty?

  # Held in an ivar so the window is not collected while it is on screen.
    def run_setup
      @setup_window = SetupWindow.new(app, @setup_backends, method(:finish_setup)).tap do |setup|
        setup.build
        if @present
          setup.present
        end
      end
    end

  # Re-activation is deferred to an idle tick rather than called straight from
  # the button handler: re-entering activate while the setup window is being
  # destroyed inside its own signal handler crashes GTK.
    def finish_setup(backend)
      @backend = backend
      @settings['did-initial-setup'] = true
      GLib::Idle.add do
        @setup_window = nil
        # Guarded: activating an application that was never registered is a
        # GLib assertion failure rather than a no-op.
        if app.registered?
          app.activate
        end
        false
      end
    end

    def setup_actions
      WINDOW_ACTIONS.each { |name, accels| add_action(
        window,
        'win',
        name,
        accels,
      ) }
      APP_ACTIONS.each { |name, accels| add_action(
        app,
        'app',
        name,
        accels,
      ) }

      add_sort_action
      add_show_contact_action

      search_button.signal_connect('toggled') { search_bar.search_mode = search_button.active? }
      search_bar.signal_connect('notify::search-mode-enabled') { search_button.active = search_bar.search_mode? }
    end

    def add_action(scope, prefix, name, accels)
      Gio::SimpleAction.new(name, nil).tap do |action|
        action.signal_connect('activate') { send(:"action_#{name.tr('-', '_')}") }
        scope.add_action(action)
        if accels.any?
          app.set_accels_for_action("#{prefix}.#{name}", accels)
        end
      end
    end

  # A stateful action, exactly like upstream's { "sort-on", null, "s", "'surname'" }.
    def add_sort_action
      Gio::SimpleAction.new(
        'sort-on',
        GLib::VariantType.new('s'),
        GLib::Variant.new(@settings['sort-on-surname'] ? 'surname' : 'first-name'),
      ).tap do |action|
        # ruby-gnome hands the action parameter over already unwrapped, so this
        # is a Ruby String rather than a GLib::Variant.
        action.signal_connect('activate') { |_, parameter| set_sort_on_surname(parameter.to_s == 'surname') }
        window.add_action(action)
        @sort_action = action
      end
    end

  # app.show-contact takes the contact id to show, which is how --individual
  # and the shell search provider ask an already-running instance to focus one.
    def add_show_contact_action
      Gio::SimpleAction.new('show-contact', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| show_contact_by_id(parameter.to_s) }
        app.add_action(action)
      end
    end

  # --- Contact lifecycle actions -----------------------------------------

    def action_new_contact
      @state = CREATING
      contact_pane_page.title = 'New Contact'
      right_header.show_title = true
      contact_pane.new_contact
      content_box.show_content = true
      update_ui_for_state
    end

    def action_edit_contact
      @store.selected_contact.then do |contact|
        if contact
          @state = UPDATING
          contact_pane_page.title = "Editing #{contact.display_name}"
          right_header.show_title = true
          contact_pane.edit_contact
          update_ui_for_state
        end
      end
    end

    def action_edit_contact_save
      editing?.then do |was_editing|
        if was_editing
          contact_pane.stop_editing(cancel: false)
          if @store.selected_contact
            @state = SHOWING
          else
            @state = NORMAL
          end
          reset_content_title
          update_ui_for_state
        end
      end
    end

    def action_cancel
      if @selection_mode
        action_cancel_selection
      else
        editing?.then do |was_editing|
          if was_editing
            contact_pane.stop_editing(cancel: true)
            if @store.selected_contact
              @state = SHOWING
            else
              @state = NORMAL
            end
            reset_content_title
            update_ui_for_state
          end
        end
      end
    end

    def action_focus_search
      search_bar.search_mode = true
      filter_entry.grab_focus
    end

    def action_delete_contact
      @store.selected_contact.then do |contact|
        if contact
          run_operation(Operations::DeleteOperation.new(@store, [contact]))
        end
        if contact
          contact_pane.show_contact(nil)
        end
      end
    end

    def action_mark_favorite = set_favorite(true)
    def action_unmark_favorite = set_favorite(false)

  # --- Selection mode -----------------------------------------------------

    def action_select_contacts
      @selection_mode = true
      contacts_list.selection_mode = true
      update_selection_ui
      update_ui_for_state
    end

    def action_cancel_selection
      @selection_mode = false
      contacts_list.selection_mode = false
      update_ui_for_state
    end

    def action_delete_marked_contacts
      @store.marked_contacts.then do |marked|
        if marked.any?
          run_operation(Operations::DeleteOperation.new(@store, marked))
          action_cancel_selection
        end
      end
    end

    def action_link_marked_contacts
      @store.marked_contacts.then do |marked|
        if marked.length > 1
          run_operation(Operations::LinkOperation.new(@store, marked)).then do |primary|
            @last_link_operation = @operations.last_reversable
            action_cancel_selection
            @store.select_contact(primary)
          end
        end
      end
    end

    def action_export_marked_contacts
      @store.marked_contacts.then do |marked|
        if marked.any?
          export_contacts(marked, 'contacts.vcf')
        end
      end
    end

    def action_export_selected_contact
      @store.selected_contact.then do |contact|
        if contact
          export_contacts([contact], "#{filename_for(contact)}.vcf")
        end
      end
    end

    def action_show_contact_qr_code
      @store.selected_contact.then do |contact|
        if contact
          QrCodeDialog.new(contact).tap do |dialog|
            dialog.build
            dialog.present(window)
          end
        end
      end
    end

  # Without Folks personas there is nothing recorded to split a contact on, so
  # unlinking reverses the most recent link, and says so when there was none.
    def action_unlink_contact
      @store.selected_contact.then do |contact|
        if contact
          Operations::UnlinkOperation.new(@store, contact, @last_link_operation).then do |operation|
            if operation.possible?
              operation.run
              @last_link_operation = nil
              show_toast(operation.description)
            else
              show_toast('This contact is not linked')
            end
          end
        end
      end
    end

    def action_undo_operation
      @operations.undo_last.then do |operation|
        if operation
          contacts_list.update_visible_page
          show_toast("Undid: #{operation.description}")
        else
          show_toast('Nothing to undo')
        end
      end
    end

  # --- Application actions ------------------------------------------------

    def action_quit
      @settings.remember(window)
      app.quit
    end

    def action_about = about_dialog.present(window)

    def action_shortcuts
      ShortcutsDialog.new.tap do |dialog|
        dialog.build
        dialog.present(window)
      end
    end

    def action_help
      Gtk::UriLauncher.new(HELP_URI).launch(window, nil) do |launcher, result|
        launcher.launch_finish(result)
      rescue GLib::Error => e
        warn "Could not open help: #{e.message}"
      end
    end

    def action_show_preferences
      PreferencesDialog.new(@store, @settings, method(:set_sort_on_surname)).tap do |dialog|
        dialog.build
        dialog.present(window)
      end
    end

    def action_import
      Gtk::FileDialog.new.tap do |dialog|
        dialog.title = 'Import Contacts'
        dialog.filters = vcard_filters
        dialog.open_multiple(window, nil) do |_, result|
          open_import_dialog(dialog.open_multiple_finish(result))
        rescue GLib::Error => e
          report_dismissable('import', e)
        end
      end
    end

    def action_export_all = export_contacts(@store.contacts, 'contacts.vcf')

  # --- Helpers ------------------------------------------------------------

    def vcard_filters
      Gio::ListStore.new(Gtk::FileFilter).tap do |filters|
        filters.append(
          Gtk::FileFilter.new.tap do |filter|
                  filter.name = 'vCard files'
                  filter.add_pattern('*.vcf')
                  filter.add_pattern('*.vcard')
                  filter.add_mime_type(VCard::MIME_TYPE)
                end,
        )
      end
    end

  # Upstream shows a preview dialog listing what each file contains before
  # anything is added, so the import can be reviewed and cancelled.
    def open_import_dialog(files)
      to_array(files).then do |list|
        if list.any?
          ImportDialog.new(list, method(:import_parsed)).tap do |dialog|
            dialog.build
            dialog.present(window)
          end
        end
      end
    end

    def import_parsed(hashes)
      run_operation(Operations::ImportOperation.new(@store, hashes)).then do
        contacts_list.update_visible_page
        @operations.last_reversable.then do |op|
          if op&.imported&.any?
            @store.select_contact(op.imported.first)
          end
        end
      end
    end

    def export_contacts(contacts, suggested_name)
      Gtk::FileDialog.new.tap do |dialog|
        if contacts.length == 1
          dialog.title = 'Export Contact'
        else
          dialog.title = 'Export Contacts'
        end
        dialog.initial_name = suggested_name
        dialog.filters = vcard_filters
        dialog.save(window, nil) do |_, result|
          write_export(dialog.save_finish(result), contacts)
        rescue GLib::Error => e
          report_dismissable('export', e)
        end
      end
    end

    def write_export(file, contacts)
      file.then do |target|
        if target
          File.write(target.path, VCard.dump_all(contacts.map(&:to_h)))
          show_toast(export_summary(contacts.length, File.basename(target.path)))
        end
      end
    rescue StandardError => e
      show_toast("Could not export: #{e.message}")
    end

    def export_summary(count, filename)
      count == 1 ? "Exported 1 contact to #{filename}" : "Exported #{count} contacts to #{filename}"
    end

    def filename_for(contact) = contact.display_name.gsub(/[^A-Za-z0-9._-]+/, '-')

  # Gio list models arrive from the file dialog; normalise them to an Array.
    def to_array(model)
      model.respond_to?(:n_items) ? (0...model.n_items).map { |i| model.get_item(i) } : Array(model)
    end

  # The file dialogs raise on cancellation too, which is not worth a toast.
    def report_dismissable(operation, error)
      unless error.message.to_s.match?(/dismiss|cancel/i)
        show_toast("Could not #{operation}: #{error.message}")
      end
    end

  # Every reversible operation offers its Undo through the toast, which is how
  # upstream surfaces win.undo-operation.
    def run_operation(operation)
      @operations.execute(operation).tap do
        contacts_list.update_visible_page
        update_ui_for_state
        operation.reversable? ? show_undo_toast(operation) : show_toast(operation.description)
      end
    end

    def set_favorite(value)
      @store.selected_contact.then do |contact|
        if contact
          @store.set_favorite(contact, value)
          update_contact_menu
          update_ui_for_state
          show_toast("#{contact.display_name} #{value ? 'marked as favourite' : 'removed from favourites'}")
        end
      end
    end

    def set_sort_on_surname(on_surname)
      @settings['sort-on-surname'] = on_surname
      @store.sort_on_surname = on_surname
      @store.send(:resort)
      @sort_action&.set_state(GLib::Variant.new(on_surname ? 'surname' : 'first-name'))
      contacts_list.refresh
    end

    def show_contact_by_id(id)
      @store.contacts.find { |c| c.id == id }.then do |contact|
        if contact
          @store.select_contact(contact)
        end
      end
    end

  # --state and UI ---------------------------------------------------------

  # --version aside, the command-line options all amount to "open showing
  # this", which is what upstream's --email/--individual/--search do.
    def apply_startup_query
      @startup_query.then do |query|
        if query && !query.to_s.empty?
          search_bar.search_mode = true
          filter_entry.text = query.to_s
        end
      end

      @startup_contact_id.then do |id|
        if id
          show_contact_by_id(id)
        end
      end
    end

  # GNOME Shell talks to the provider over the connection the application
  # already owns, exactly as upstream registers it from dbus_register.
    def register_search_provider
      app.dbus_connection.then do |connection|
        if connection && @search_provider_enabled
          search_provider.register(connection)
        end
      end
    rescue StandardError, GLib::Error => e
      warn "Search provider unavailable: #{e.message}"
    end

    def search_provider
      @search_provider ||= ShellSearchProvider.new(
        @store,
        on_activate: method(:show_contact_by_id),
        on_launch:   method(:launch_search),
      )
    end

    def launch_search(query)
      search_bar.search_mode = true
      filter_entry.text = query.to_s
      window.present
    end

    def on_selection_changed
      @store.selected_contact.then do |contact|
        if contact
          @state = SHOWING
          contact_pane.show_contact(contact, suggestions: suggestions_for(contact))
          content_box.show_content = true
          update_contact_menu
        else
          @state = NORMAL
          contact_pane.show_contact(nil)
        end
        update_ui_for_state
      end
    end

  # Only suggest links the user has not already dismissed for this contact.
    def suggestions_for(contact)
      @store.link_suggestions_for(contact)
            .reject { |other| @rejected_suggestions[contact.id]&.include?(other.id) }
    end

    def accept_suggestion(suggestion)
      @store.selected_contact.then do |contact|
        if contact
          run_operation(Operations::LinkOperation.new(@store, [contact, suggestion])).then do |primary|
            @last_link_operation = @operations.last_reversable
            @store.select_contact(primary)
            on_selection_changed
          end
        end
      end
    end

    def reject_suggestion(suggestion)
      @store.selected_contact.then do |contact|
        if contact
          (@rejected_suggestions[contact.id] ||= []) << suggestion.id
          contact_pane.show_contact(contact, suggestions: suggestions_for(contact))
        end
      end
    end

    def on_contact_saved(contact_data)
      @store.selected_contact.then do |existing|
        if existing && @state == UPDATING
          @store.update_contact(existing, **contact_data)
          contact_pane.show_contact(existing, suggestions: suggestions_for(existing))
        else
          @store.select_contact(@store.add_contact(**contact_data))
        end
        contacts_list.update_visible_page
      end
    end

    def update_contact_menu
      @store.selected_contact.then do |contact|
        if contact
          contact_menu_button.menu_model = contact_menu(contact)
        end
      end
    end

  # The same per-contact menu upstream defines in contacts-main-window.blp.
    def contact_menu(contact)
      Gio::Menu.new.tap do |menu|
        menu.append_section(
          nil,
          Gio::Menu.new.tap do |section|
                  if contact.favorite?
                    section.append('Unmark as Favorite', 'win.unmark-favorite')
                  else
                    section.append('Mark as Favorite', 'win.mark-favorite')
                  end
                  section.append('Share as QR Code', 'win.show-contact-qr-code')
                end,
        )

        menu.append_section(
          nil,
          Gio::Menu.new.tap do |section|
                  section.append('Export', 'win.export-selected-contact')
                  section.append('Unlink', 'win.unlink-contact')
                  section.append('Delete Contact', 'win.delete-contact')
                end,
        )
      end
    end

    def reset_content_title
      contact_pane_page.title = @store.selected_contact&.display_name || 'Select a Contact'
      right_header.show_title = false
    end

    def show_toast(message) = toast_overlay.add_toast(Adwaita::Toast.new(message))

    def show_undo_toast(operation)
      toast_overlay.add_toast(
        Adwaita::Toast.new(operation.description).tap do |toast|
              toast.button_label = '_Undo'
              toast.signal_connect('button-clicked') { undo_operation(operation.uuid) }
            end,
      )
    end

    def undo_operation(uuid)
      @operations.undo(uuid).then do |operation|
        if operation
          contacts_list.update_visible_page
          update_ui_for_state
        end
      end
    end

    def editing? = @state == CREATING || @state == UPDATING

    def update_ui_for_state
      left_header.visible = !@selection_mode
      selection_header.visible = @selection_mode

      add_button.visible = !editing?
      search_button.visible = !editing?
      select_button.visible = !editing? && !@store.empty?
      primary_menu_button.visible = !editing?

      contact_sheet_buttons.visible = (@state == SHOWING && !@selection_mode)
      cancel_button.visible = editing?
      done_button.visible = editing?
      if @state == CREATING
        done_button.label = '_Add'
      else
        done_button.label = '_Done'
      end

      right_header.show_end_title_buttons = !editing?

      actions_bar.reveal_child = @selection_mode || (@state == SHOWING)
      update_action_buttons
      filter_entry.sensitive = !editing?
    end

    def update_action_buttons
      favorite_button.visible = !@selection_mode
      link_button.visible = @selection_mode

      if @selection_mode
        export_button.action_name = 'win.export-marked-contacts'
        delete_button.action_name = 'win.delete-marked-contacts'
        update_selection_ui
      else
        export_button.action_name = 'win.export-selected-contact'
        delete_button.action_name = 'win.delete-contact'
        # Sensitivity is set from the marked count while selection mode is on,
        # so it has to be restored on the way out or the bar stays dead.
        enable_single_contact_buttons
      end

      @store.selected_contact.then do |contact|
        if contact&.favorite?
          favorite_button.label = '_Remove Favourite'
        else
          favorite_button.label = '_Favourite'
        end
        if contact&.favorite?
          favorite_button.action_name = 'win.unmark-favorite'
        else
          favorite_button.action_name = 'win.mark-favorite'
        end
      end
    end

    # Outside selection mode the bottom bar acts on the selected contact, so it
    # is live exactly when there is one.
    def enable_single_contact_buttons
      @store.selected_contact.then do |contact|
        [favorite_button, export_button, delete_button].each do |button|
          button.sensitive = !contact.nil?
        end
      end
    end

    def update_selection_ui
      @store.marked_contacts.length.then do |count|
        if count.zero?
          selection_title.title = 'Select Contacts'
        else
          selection_title.title = "#{count} Selected"
        end
        link_button.sensitive = count > 1
        export_button.sensitive = count.positive?
        delete_button.sensitive = count.positive?
      end
    end
end
