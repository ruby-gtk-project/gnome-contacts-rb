# frozen_string_literal: true

require 'gtk4'
require 'securerandom'

require_relative 'contact'
require_relative 'contact_store'
require_relative 'contact_pane'
require_relative 'contact_editor'

# ContactsApp is the main application class.
#
class ContactsApp
  def initialize(backend: nil)
    @store = ContactStore.new(backend: backend)
  end

  def build
    app.tap do
      app.signal_connect('activate') do
        @store.load

        app.add_window(window)

        window.tap do |win|
          win.titlebar = header_bar
          win.child = main_box

          main_box.tap do |box|
            box.append(info_bar)
            box.append(paned)

            info_bar.tap do |ib|
              ib.add_child(info_bar_label)
              ib.add_button('Undo', 1)
              ib.signal_connect('response') { |_, id| handle_undo(id) }
            end

            paned.tap do |p|
              p.start_child = list_frame
              p.end_child = contact_pane.build

              list_frame.tap do |f|
                f.child = scrolled_list

                scrolled_list.tap do |sw|
                  sw.child = list_view
                end
              end
            end
          end

          header_bar.tap do |hb|
            hb.pack_start(search_button)
            hb.pack_end(add_button)
            hb.title_widget = title_box

            title_box.tap do |tb|
              tb.append(title_label)
              tb.append(search_entry)

              search_entry.tap do |entry|
                entry.signal_connect('search-changed') { @store.query = entry.text }
                entry.signal_connect('stop-search') do
                  search_button.active = false
                  entry.text = ''
                end
              end
            end

            search_button.tap do |btn|
              btn.signal_connect('toggled') do
                search_entry.visible = btn.active?
                title_label.visible = !btn.active?
                search_entry.grab_focus if btn.active?
              end
            end

            add_button.tap do |btn|
              btn.signal_connect('clicked') { show_add_dialog }
            end
          end

          list_view.tap do |lv|
            lv.model = @store.selection_model
            lv.factory = list_factory
          end

          @store.selection_model.tap do |sm|
            sm.signal_connect('notify::selected') { show_selected_contact }
          end
        end

        show_selected_contact
        window.present
      end
    end
  end

  def run = app.run

  # Memoized widget methods with styles

  def app = @app ||= Gtk::Application.new('org.example.contacts', :default_flags)
  def window
    @window ||= Gtk::ApplicationWindow.new(app).tap do |win|
      win.title = 'Contacts'
      win.set_default_size(900, 600)
    end
  end

  def main_box
    @main_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.vexpand = true
    end
  end

  def info_bar
    @info_bar ||= Gtk::InfoBar.new.tap do |ib|
      ib.revealed = false
      ib.message_type = :info
    end
  end

  def info_bar_label = @info_bar_label ||= Gtk::Label.new
  def header_bar = @header_bar ||= Gtk::HeaderBar.new
  def title_box = @title_box ||= Gtk::Box.new(:horizontal, 0)

  def title_label
    @title_label ||= Gtk::Label.new.tap do |l|
      l.label = 'Contacts'
      l.add_css_class('title')
    end
  end

  def search_button
    @search_button ||= Gtk::ToggleButton.new.tap do |btn|
      btn.icon_name = 'system-search-symbolic'
    end
  end

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.placeholder_text = 'Search contacts…'
      entry.hexpand = true
      entry.max_width_chars = 40
      entry.visible = false
    end
  end

  def add_button
    @add_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'list-add-symbolic'
    end
  end

  def paned
    @paned ||= Gtk::Paned.new(:horizontal).tap do |p|
      p.vexpand = true
      p.position = 300
    end
  end

  def list_frame = @list_frame ||= Gtk::Frame.new

  def scrolled_list
    @scrolled_list ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.hscrollbar_policy = :never
    end
  end

  def list_view
    @list_view ||= Gtk::ListView.new.tap do |lv|
      lv.add_css_class('navigation-sidebar')
    end
  end

  def contact_pane
    @contact_pane ||= ContactPane.new(
      on_edit: -> { show_edit_dialog },
      on_delete: -> { delete_selected_contact }
    )
  end

  def list_factory
    @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect('setup') do |_, item|
        item.child = Gtk::Box.new(:horizontal, 12).tap do |box|
          box.margin_top = 8
          box.margin_bottom = 8
          box.margin_start = 12
          box.margin_end = 12
          box.append(Gtk::Frame.new.tap do |frame|
            frame.add_css_class('circular')
            frame.child = Gtk::Label.new.tap { |l| l.set_size_request(32, 32) }
          end)
          box.append(Gtk::Label.new.tap { |l| l.xalign = 0; l.hexpand = true })
        end
      end

      f.signal_connect('bind') do |_, item|
        item.item.then do |contact|
          item.child.tap do |box|
            box.first_child.tap do |avatar_frame|
              avatar_frame.child.label = contact.initials
              avatar_frame.next_sibling.label = contact.display_name
            end
          end
        end
      end
    end
  end

  private

  def show_selected_contact
    contact_pane.show_contact(@store.selected_contact)
  end

  def show_add_dialog
    ContactEditor.new(
      contact: nil,
      on_save: ->(data) { @store.select_contact(@store.add_contact(**data)) },
      on_cancel: -> { }
    ).tap do |editor|
      editor.build
      editor.present(window)
    end
  end

  def show_edit_dialog
    @store.selected_contact.then do |contact|
      if contact
        ContactEditor.new(
          contact: contact,
          on_save: ->(data) { update_contact(data) },
          on_cancel: -> { }
        ).tap do |editor|
          editor.build
          editor.present(window)
        end
      end
    end
  end

  def update_contact(data)
    @store.selected_contact.then do |contact|
      if contact
        @store.update_contact(contact, **data)
        contact_pane.show_contact(contact)
      end
    end
  end

  def delete_selected_contact
    @store.selected_contact.then do |contact|
      if contact
        @deleted_undo_info = @store.delete_contact(contact)
        contact_pane.show_contact(nil)
        info_bar_label.label = "Deleted #{contact.display_name}"
        info_bar.revealed = true

        GLib::Timeout.add_seconds(5) do
          info_bar.revealed = false if info_bar.revealed?
          @deleted_undo_info = nil
          false
        end
      end
    end
  end

  def handle_undo(response_id)
    @deleted_undo_info.then do |undo_info|
      if response_id == 1 && undo_info
        @store.select_contact(@store.restore_contact(undo_info))
      end
    end
    info_bar.revealed = false
    @deleted_undo_info = nil
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

  ContactsApp.new(backend: backend).build.run
end
