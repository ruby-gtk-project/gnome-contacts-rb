# frozen_string_literal: true

require 'adwaita'

# PreferencesDialog shows the address books the app is reading from, and the
# sort order.
#
# Ported from upstream's src/contacts-preferences-window.vala and
# data/ui/contacts-preferences-window.blp, which is an Adw.PreferencesDialog
# with a single "Address Books" page. Upstream lists the Evolution Data Server
# sources and lets you enable or disable each; here there is one address book —
# the active backend — so the page reports it and where its data lives.
#
class PreferencesDialog < Adwaita::PreferencesDialog
  def initialize(store, settings, on_sort_changed)
    super()
    self.title = 'Preferences'
    @store = store
    @settings = settings
    @on_sort_changed = on_sort_changed
  end

  def build
    tap do |dialog|
      dialog.add(address_books_page)

      address_books_page.tap do |page|
        page.add(address_books_group)
        page.add(display_group)

        address_books_group.tap do |group|
          group.add(backend_row)

          backend_row.tap do |row|
            row.title = @store.backend.display_name
            row.subtitle = @store.backend.location
          end
        end

        display_group.tap do |group|
          group.add(sort_row)

          sort_row.tap do |row|
            if @settings['sort-on-surname']
              row.selected = 1
            else
              row.selected = 0
            end
            row.signal_connect('notify::selected') { @on_sort_changed.call(row.selected == 1) }
          end
        end
      end
    end
  end

  # Memoized widget methods

  def address_books_page
    @address_books_page ||= Adwaita::PreferencesPage.new.tap do |page|
      page.title = 'Address Books'
      page.icon_name = 'address-book-new-symbolic'
    end
  end

  def address_books_group
    @address_books_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Address Books'
      group.description = 'Where your contacts are stored'
    end
  end

  def backend_row
    @backend_row ||= Adwaita::ActionRow.new.tap do |row|
      row.subtitle_lines = 2
      row.add_prefix(Gtk::Image.new(icon_name: 'folder-symbolic'))
      row.add_suffix(contact_count_label)
    end
  end

  def contact_count_label
    @contact_count_label ||= Gtk::Label.new.tap do |label|
      label.label = "#{@store.n_contacts} contacts"
      label.valign = :center
      label.add_css_class('dim-label')
    end
  end

  def display_group
    @display_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Display'
    end
  end

  def sort_row
    @sort_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = 'List Contacts By'
      row.model = Gtk::StringList.new(['First Name', 'Surname'])
    end
  end
end
