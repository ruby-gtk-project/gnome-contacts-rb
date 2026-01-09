# frozen_string_literal: true

require 'adwaita'

require_relative 'contact'
require_relative 'contact_store'
require_relative 'contact_pane'
require_relative 'contact_list'

# App is the main application class.
#
class App
  NORMAL   = :normal
  SHOWING  = :showing
  CREATING = :creating
  UPDATING = :updating

  def initialize(backend: nil)
    @backend = backend
    @state = NORMAL
  end

  def build
    app.tap do |a|
      a.signal_connect('activate') do
        @store = ContactStore.new(backend: @backend)
        @store.load

        a.add_window(window)

        window.tap do |win|
          win.title = 'Contacts'
          win.set_default_size(800, 600)
          win.child = toast_overlay

          toast_overlay.tap do |to|
            to.child = content_box

            content_box.tap do |cb|
              cb.sidebar = list_pane_page
              cb.content = contact_pane_page

              list_pane_page.tap do |lpp|
                sidebar_toolbar.tap do |st|
                  st.add_top_bar(left_header)
                  st.add_top_bar(search_bar_container)
                  st.content = contacts_list.build
                  st.add_bottom_bar(actions_bar)

                  left_header.tap do |hb|
                    hb.pack_start(add_button)
                    hb.pack_end(primary_menu_button)

                    add_button.tap do |btn|
                      btn.signal_connect('clicked') { new_contact }
                    end
                  end

                  search_bar_container.tap do |sbc|
                    sbc.child = filter_entry

                    filter_entry.tap do |fe|
                      fe.signal_connect('search-changed') do
                        @store.query = fe.text
                      end
                    end
                  end

                  actions_bar.tap do |ab|
                    ab.child = actions_box

                    actions_box.tap do |box|
                      box.append(delete_button)

                      delete_button.tap do |btn|
                        btn.signal_connect('clicked') { delete_selected_contact }
                      end
                    end
                  end
                end
              end

              contact_pane_page.tap do |cpp|
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

                      edit_button.tap do |btn|
                        btn.signal_connect('clicked') { edit_contact }
                      end
                    end

                    cancel_button.tap do |btn|
                      btn.signal_connect('clicked') { cancel_editing }
                    end

                    done_button.tap do |btn|
                      btn.signal_connect('clicked') { save_contact }
                    end
                  end
                end
              end
            end
          end

          @store.selection_model.tap do |sm|
            sm.signal_connect('notify::selected') { on_selection_changed }
          end

          setup_actions
          update_ui_for_state
          window.present
        end
      end
    end
  end

  def run
    app.run([])
  end

  # Memoized widget methods

  def app
    @app ||= begin
      Adwaita.init
      Gtk::Application.new('org.example.contacts', :default_flags)
    end
  end

  def window
    @window ||= Gtk::ApplicationWindow.new(app)
  end

  def toast_overlay
    @toast_overlay ||= Adwaita::ToastOverlay.new
  end

  def content_box
    @content_box ||= Adwaita::NavigationSplitView.new.tap do |cb|
      cb.sidebar_width_fraction = 0.3
      cb.min_sidebar_width = 260
      cb.max_sidebar_width = 360
    end
  end

  def list_pane_page
    @list_pane_page ||= Adwaita::NavigationPage.new(sidebar_toolbar, 'Contacts')
  end

  def sidebar_toolbar
    @sidebar_toolbar ||= Adwaita::ToolbarView.new
  end

  def left_header
    @left_header ||= Adwaita::HeaderBar.new
  end

  def add_button
    @add_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'list-add-symbolic'
      btn.tooltip_text = 'Add New Contact'
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
      menu.append('_Import From File…', 'app.import')
      menu.append('_Export All Contacts…', 'app.export-all')
    end
  end

  def search_bar_container
    @search_bar_container ||= Adwaita::Bin.new.tap do |sbc|
      sbc.add_css_class('toolbar')
    end
  end

  def filter_entry
    @filter_entry ||= Gtk::SearchEntry.new.tap do |fe|
      fe.placeholder_text = 'Search contacts'
    end
  end

  def contacts_list
    @contacts_list ||= ContactList.new(@store)
  end

  def actions_bar
    @actions_bar ||= Gtk::Revealer.new.tap do |ab|
      ab.reveal_child = false
      ab.transition_type = :slide_up
    end
  end

  def actions_box
    @actions_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.add_css_class('toolbar')
      box.margin_start = 6
      box.margin_end = 6
    end
  end

  def delete_button
    @delete_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Delete'
      btn.use_underline = true
      btn.add_css_class('destructive-action')
    end
  end

  def contact_pane_page
    @contact_pane_page ||= Adwaita::NavigationPage.new(content_toolbar, 'Select a Contact')
  end

  def content_toolbar
    @content_toolbar ||= Adwaita::ToolbarView.new
  end

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
      btn.tooltip_text = 'Edit Contact'
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
    @contact_pane ||= ContactPane.new(@store, method(:on_contact_saved))
  end

  def setup_actions
    # Delete contact action
    Gio::SimpleAction.new('delete-contact', nil).tap do |action|
      action.signal_connect('activate') { delete_selected_contact }
      window.add_action(action)
    end

    # Mark as favorite action
    Gio::SimpleAction.new('mark-favorite', nil).tap do |action|
      action.signal_connect('activate') { mark_favorite }
      window.add_action(action)
    end

    # Unmark as favorite action
    Gio::SimpleAction.new('unmark-favorite', nil).tap do |action|
      action.signal_connect('activate') { unmark_favorite }
      window.add_action(action)
    end
  end

  def update_contact_menu
    @store.selected_contact.then do |contact|
      if contact
        Gio::Menu.new.tap do |menu|
          # Favorite section
          Gio::Menu.new.tap do |fav_section|
            if contact.favorite?
              fav_section.append('Unmark as Favorite', 'win.unmark-favorite')
            else
              fav_section.append('Mark as Favorite', 'win.mark-favorite')
            end
            menu.append_section(nil, fav_section)
          end

          # Delete section
          Gio::Menu.new.tap do |del_section|
            del_section.append('Delete Contact', 'win.delete-contact')
            menu.append_section(nil, del_section)
          end

          contact_menu_button.menu_model = menu
        end
      end
    end
  end

  private

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

  def new_contact
    @state = CREATING
    contact_pane_page.title = 'New Contact'
    right_header.show_title = true
    contact_pane.new_contact
    content_box.show_content = true
    update_ui_for_state
  end

  def edit_contact
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

  def cancel_editing
    contact_pane.stop_editing(cancel: true)
    @store.selected_contact.then do |contact|
      @state = contact ? SHOWING : NORMAL
    end
    contact_pane_page.title = 'Select a Contact'
    right_header.show_title = false
    update_ui_for_state
  end

  def save_contact
    contact_pane.stop_editing(cancel: false)
    @state = SHOWING
    contact_pane_page.title = 'Select a Contact'
    right_header.show_title = false
    update_ui_for_state
  end

  def on_contact_saved(contact_data)
    @store.selected_contact.then do |existing|
      if existing && existing.id == contact_data[:id]
        @store.update_contact(existing, **contact_data)
        contact_pane.show_contact(existing)
      else
        @store.add_contact(**contact_data).tap do |new_contact|
          @store.select_contact(new_contact)
        end
      end
    end
  end

  def delete_selected_contact
    @store.selected_contact.then do |contact|
      if contact
        @deleted_info = @store.delete_contact(contact)
        contact_pane.show_contact(nil)
        show_undo_toast("Deleted #{contact.display_name}")
      end
    end
  end

  def mark_favorite
    @store.selected_contact.then do |contact|
      if contact
        @store.set_favorite(contact, true)
        update_contact_menu
        show_toast("#{contact.display_name} marked as favorite")
      end
    end
  end

  def unmark_favorite
    @store.selected_contact.then do |contact|
      if contact
        @store.set_favorite(contact, false)
        update_contact_menu
        show_toast("#{contact.display_name} unmarked as favorite")
      end
    end
  end

  def show_toast(message)
    Adwaita::Toast.new(message).tap do |toast|
      toast_overlay.add_toast(toast)
    end
  end

  def show_undo_toast(message)
    Adwaita::Toast.new(message).tap do |toast|
      toast.button_label = '_Undo'
      toast.signal_connect('button-clicked') { undo_delete }
      toast_overlay.add_toast(toast)
    end
  end

  def undo_delete
    @deleted_info.then do |info|
      if info
        @store.restore_contact(info).tap do |contact|
          @store.select_contact(contact)
        end
        @deleted_info = nil
      end
    end
  end

  def editing?
    @state == CREATING || @state == UPDATING
  end

  def update_ui_for_state
    add_button.visible = !editing?
    primary_menu_button.visible = !editing?

    contact_sheet_buttons.visible = (@state == SHOWING)
    cancel_button.visible = editing?
    done_button.visible = editing?

    done_button.label = (@state == CREATING) ? '_Add' : '_Done'

    right_header.show_end_title_buttons = !editing?

    filter_entry.sensitive = !editing?
  end
end

if __FILE__ == $PROGRAM_NAME
  backend_type = ARGV[0]&.to_sym || :json

  backend = case backend_type
            when :vcard
              require_relative 'vcard_backend'
              Backends::VCardBackend.new
            else
              require_relative 'json_backend'
              Backends::JsonBackend.new
            end

  puts "Using backend: #{backend.display_name}"
  puts "Data location: #{backend.location}"

  App.new(backend: backend).build.run
end
