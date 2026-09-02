# frozen_string_literal: true

require 'adwaita'

require_relative 'contact'
require_relative 'contact_store'
require_relative 'contact_pane'
require_relative 'contact_list'
require_relative 'vcard'

# App is the main application class.
#
# Ported from upstream's src/contacts-main-window.vala and
# data/ui/contacts-main-window.blp: a navigation split view with the contact
# list in the sidebar and the sheet/editor in the content pane, driven by a
# four-state machine.
#
class App
  APP_ID = 'org.gnome.ContactsRb'
  NORMAL   = :normal
  SHOWING  = :showing
  CREATING = :creating
  UPDATING = :updating

  # action name => [accelerators, handler]
  WINDOW_ACTIONS = {
    'new-contact' => ['<Control>n'],
    'edit-contact' => ['<Control>e'],
    'delete-contact' => ['Delete'],
    'search' => ['<Control>f'],
    'cancel' => ['Escape'],
    'mark-favorite' => [],
    'unmark-favorite' => []
  }.freeze

  APP_ACTIONS = {
    'import' => ['<Control>i'],
    'export-all' => ['<Control><Shift>e'],
    'about' => ['F1'],
    'quit' => ['<Control>q', '<Control>w']
  }.freeze

  # app_id/flags are injectable so tests can register a throwaway, non-unique
  # application instead of talking to the session's real one; present: false
  # builds the whole widget tree without ever mapping the window, so a test run
  # does not flash a window onto the user's desktop for every example.
  def initialize(backend: nil, app_id: APP_ID, flags: :default_flags, present: true)
    @backend = backend
    @app_id = app_id
    @flags = flags
    @present = present
    @state = NORMAL
  end

  def build
    app.tap do |a|
      a.signal_connect('activate') do
        @store = ContactStore.new(backend: @backend)
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
                  st.add_top_bar(search_bar)
                  st.content = contacts_list.build
                  st.add_bottom_bar(actions_bar)

                  left_header.tap do |hb|
                    hb.pack_start(add_button)
                    hb.pack_end(primary_menu_button)
                    hb.pack_end(search_button)
                  end

                  search_bar.tap do |sb|
                    sb.child = filter_entry
                    sb.connect_entry(filter_entry)
                    sb.key_capture_widget = window

                    filter_entry.tap do |fe|
                      fe.signal_connect('search-changed') do
                        @store.query = fe.text
                        contacts_list.update_visible_page
                      end
                    end
                  end

                  actions_bar.tap do |ab|
                    ab.child = actions_box

                    actions_box.tap do |box|
                      box.append(favorite_button)
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
        end

        setup_actions
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
  # titlebar of its own, and it also keeps Adwaita::Dialog (the about dialog)
  # inside the window instead of spawning a second toplevel.
  #
  # (Adwaita::Application is still broken in the bindings, so the application
  # object above stays a Gtk::Application.)
  def window
    @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
      win.title = 'Contacts'
      win.icon_name = 'address-book-new-symbolic'
      win.set_default_size(900, 640)
    end
  end

  def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

  def content_box
    @content_box ||= Adwaita::NavigationSplitView.new.tap do |cb|
      cb.sidebar_width_fraction = 0.3
      cb.min_sidebar_width = 260
      cb.max_sidebar_width = 360
    end
  end

  def list_pane_page = @list_pane_page ||= Adwaita::NavigationPage.new(sidebar_toolbar, 'Contacts')
  def sidebar_toolbar = @sidebar_toolbar ||= Adwaita::ToolbarView.new
  def left_header = @left_header ||= Adwaita::HeaderBar.new

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

  def primary_menu_button
    @primary_menu_button ||= Gtk::MenuButton.new.tap do |btn|
      btn.icon_name = 'open-menu-symbolic'
      btn.tooltip_text = 'Main Menu'
      btn.menu_model = primary_menu
      btn.add_css_class('flat')
    end
  end

  def primary_menu
    @primary_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, Gio::Menu.new.tap do |section|
        section.append('_Import From File…', 'app.import')
        section.append('_Export All Contacts…', 'app.export-all')
      end)

      menu.append_section(nil, Gio::Menu.new.tap do |section|
        section.append('_About Contacts', 'app.about')
      end)
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

  def contact_pane = @contact_pane ||= ContactPane.new(@store, method(:on_contact_saved))

  def about_dialog
    @about_dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_name = 'Contacts'
      about.application_icon = 'address-book-new-symbolic'
      about.developer_name = 'The Ruby GTK Project'
      about.version = '0.1.0'
      about.comments = "A Ruby port of GNOME Contacts, built with gtk4 and libadwaita.\n\n" \
                       "Shortcuts:\n" \
                       "Ctrl+N  New contact\nCtrl+E  Edit contact\nCtrl+F  Search\n" \
                       "Delete  Delete contact\nCtrl+I  Import vCards\nCtrl+Shift+E  Export all\n" \
                       'Escape  Cancel editing'
      about.website = 'https://github.com/ruby-gtk-project/gnome-contacts-rb'
      about.license_type = Gtk::License::GPL_2_0
    end
  end

  private

  # Parenthesised deliberately: in an endless method a trailing `if` would
  # modify the `def` itself, so the method would never be defined at all.
  def show_window = (window.present if @present)

  def setup_actions
    WINDOW_ACTIONS.each do |name, accels|
      Gio::SimpleAction.new(name, nil).tap do |action|
        action.signal_connect('activate') { send(:"action_#{name.tr('-', '_')}") }
        window.add_action(action)
        app.set_accels_for_action("win.#{name}", accels) if accels.any?
      end
    end

    APP_ACTIONS.each do |name, accels|
      Gio::SimpleAction.new(name, nil).tap do |action|
        action.signal_connect('activate') { send(:"action_#{name.tr('-', '_')}") }
        app.add_action(action)
        app.set_accels_for_action("app.#{name}", accels) if accels.any?
      end
    end

    search_button.signal_connect('toggled') { search_bar.search_mode = search_button.active? }
    search_bar.signal_connect('notify::search-mode-enabled') { search_button.active = search_bar.search_mode? }
    done_button.signal_connect('clicked') { save_contact }
  end

  # --- Actions ------------------------------------------------------------

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

  def action_cancel
    editing?.then do |was_editing|
      if was_editing
        contact_pane.stop_editing(cancel: true)
        @state = @store.selected_contact ? SHOWING : NORMAL
        reset_content_title
        update_ui_for_state
      end
    end
  end

  def action_search
    search_bar.search_mode = true
    filter_entry.grab_focus
  end

  def action_delete_contact
    @store.selected_contact.then do |contact|
      if contact
        @deleted_info = @store.delete_contact(contact)
        contact_pane.show_contact(nil)
        contacts_list.update_visible_page
        show_undo_toast("Deleted #{contact.display_name}")
      end
    end
  end

  def action_mark_favorite = set_favorite(true)
  def action_unmark_favorite = set_favorite(false)

  def action_quit = app.quit

  def action_about = about_dialog.present(window)

  def action_import
    Gtk::FileDialog.new.tap do |dialog|
      dialog.title = 'Import Contacts'
      dialog.filters = vcard_filters
      dialog.open(window, nil) do |_, result|
        import_file(dialog.open_finish(result))
      rescue GLib::Error => e
        report_dismissable('import', e)
      end
    end
  end

  def action_export_all
    Gtk::FileDialog.new.tap do |dialog|
      dialog.title = 'Export All Contacts'
      dialog.initial_name = 'contacts.vcf'
      dialog.filters = vcard_filters
      dialog.save(window, nil) do |_, result|
        export_to_file(dialog.save_finish(result))
      rescue GLib::Error => e
        report_dismissable('export', e)
      end
    end
  end

  # --- Action helpers -----------------------------------------------------

  def vcard_filters
    Gio::ListStore.new(Gtk::FileFilter).tap do |filters|
      filters.append(Gtk::FileFilter.new.tap do |filter|
        filter.name = 'vCard files'
        filter.add_pattern('*.vcf')
        filter.add_pattern('*.vcard')
        filter.add_mime_type(VCard::MIME_TYPE)
      end)
    end
  end

  def import_file(file)
    file.then do |target|
      if target
        @store.import(VCard.parse_all(File.read(target.path))).then do |imported|
          contacts_list.update_visible_page
          @store.select_contact(imported.first) if imported.any?
          show_toast(import_summary(imported.length))
        end
      end
    end
  rescue StandardError => e
    show_toast("Could not import: #{e.message}")
  end

  def import_summary(count)
    case count
    when 0 then 'No new contacts to import'
    when 1 then 'Imported 1 contact'
    else "Imported #{count} contacts"
    end
  end

  def export_to_file(file)
    file.then do |target|
      if target
        File.write(target.path, VCard.dump_all(@store.contacts.map(&:to_h)))
        show_toast("Exported #{@store.n_contacts} contacts to #{File.basename(target.path)}")
      end
    end
  rescue StandardError => e
    show_toast("Could not export: #{e.message}")
  end

  # The file dialogs raise on cancellation too, which is not worth a toast.
  def report_dismissable(operation, error)
    show_toast("Could not #{operation}: #{error.message}") unless error.message.to_s.match?(/dismiss|cancel/i)
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

  # --- State --------------------------------------------------------------

  def on_selection_changed
    @store.selected_contact.then do |contact|
      if contact
        @state = SHOWING
        contact_pane.show_contact(contact)
        content_box.show_content = true
        update_contact_menu
      else
        @state = NORMAL
        contact_pane.show_contact(nil)
      end
      update_ui_for_state
    end
  end

  def save_contact
    contact_pane.stop_editing(cancel: false)
    @state = @store.selected_contact ? SHOWING : NORMAL
    reset_content_title
    update_ui_for_state
  end

  def on_contact_saved(contact_data)
    @store.selected_contact.then do |existing|
      if existing && @state == UPDATING
        @store.update_contact(existing, **contact_data)
        contact_pane.show_contact(existing)
      else
        @store.select_contact(@store.add_contact(**contact_data))
      end
      contacts_list.update_visible_page
    end
  end

  def update_contact_menu
    @store.selected_contact.then do |contact|
      if contact
        contact_menu_button.menu_model = Gio::Menu.new.tap do |menu|
          menu.append_section(nil, Gio::Menu.new.tap do |section|
            if contact.favorite?
              section.append('Remove From Favourites', 'win.unmark-favorite')
            else
              section.append('Mark as Favourite', 'win.mark-favorite')
            end
          end)

          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('Delete Contact', 'win.delete-contact')
          end)
        end
      end
    end
  end

  def reset_content_title
    contact_pane_page.title = @store.selected_contact&.display_name || 'Select a Contact'
    right_header.show_title = false
  end

  def show_toast(message) = toast_overlay.add_toast(Adwaita::Toast.new(message))

  def show_undo_toast(message)
    toast_overlay.add_toast(Adwaita::Toast.new(message).tap do |toast|
      toast.button_label = '_Undo'
      toast.signal_connect('button-clicked') { undo_delete }
    end)
  end

  def undo_delete
    @deleted_info.then do |info|
      if info
        @store.select_contact(@store.restore_contact(info))
        contacts_list.update_visible_page
        @deleted_info = nil
      end
    end
  end

  def editing? = @state == CREATING || @state == UPDATING

  def update_ui_for_state
    add_button.visible = !editing?
    search_button.visible = !editing?
    primary_menu_button.visible = !editing?

    contact_sheet_buttons.visible = (@state == SHOWING)
    cancel_button.visible = editing?
    done_button.visible = editing?
    done_button.label = @state == CREATING ? '_Add' : '_Done'

    right_header.show_end_title_buttons = !editing?

    actions_bar.reveal_child = (@state == SHOWING)
    favorite_button.tap do |btn|
      @store.selected_contact.then do |contact|
        btn.label = contact&.favorite? ? '_Remove Favourite' : '_Favourite'
        btn.action_name = contact&.favorite? ? 'win.unmark-favorite' : 'win.mark-favorite'
      end
    end

    filter_entry.sensitive = !editing?
  end
end

if __FILE__ == $PROGRAM_NAME
  require_relative 'json_backend'
  require_relative 'vcard_backend'

  (ARGV[0]&.to_sym == :vcard ? Backends::VCardBackend.new : Backends::JsonBackend.new).tap do |backend|
    puts "Using backend: #{backend.display_name}"
    puts "Data location: #{backend.location}"

    App.new(backend: backend).build.run
  end
end
