# frozen_string_literal: true

# Drives the real application through the features added in the port, one step
# per turn of the GTK main loop, and writes a screenshot of each state.
#
#   env -u DISPLAY -u WAYLAND_DISPLAY ruby test/drive_main_window.rb
#
# Runs headlessly: GTK4 renders to an offscreen surface, so the PNGs under
# tmp/shots are what a real session would look like.

require 'tmpdir'
require 'fileutils'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# A scratch home so a drive never reads or scribbles on the real address book.
Dir.mktmpdir('contacts-drive').tap do |dir|
  ENV['XDG_CONFIG_HOME'] = File.join(dir, 'config')
  ENV['XDG_DATA_HOME'] = File.join(dir, 'data')
end

require 'main'
require 'json_backend'
require 'settings'
require_relative 'gtk_driver'

DIR = Dir.mktmpdir('contacts-drive-store')
BACKEND = Backends::JsonBackend.new(path: File.join(DIR, 'contacts.json'))
SETTINGS = Settings.new(path: File.join(DIR, 'settings.json'))

ADA = {
  name:            'Ada Lovelace',
  nickname:        'Ada',
  structured_name: {
    given:      'Ada',
    family:     'Lovelace',
    additional: 'Byron',
    prefixes:   'Ms',
    suffixes:   'FRS',
  },
  emails:          [{ value: 'ada@analytical.engine', type: 'Work' }],
  phones:          [{ value: '+44 20 7946 0100', type: 'Mobile' },
           { value: '+44 20 7946 0199', type: 'Work Fax' }
],
  im_addresses:    [{ value: 'ada@jabber.org', service: 'jabber' },
                 { value: 'adalove', service: 'skype' }
],
  urls:            [{ value: 'analytical.engine', type: 'Work' }],
  addresses:       [{ value: '12 Marylebone Rd, London', type: 'Home' }],
  roles:           [{ organization: 'Analytical Engine Co', title: 'Mathematician', type: 'Work' }],
  notes:           [{ value: 'First programmer; wrote note G in 1843.', type: 'Home' }],
  birthday:        '1815-12-10',
  favorite:        true,
}.freeze

# Reads the tick state of each realised row, so the drive can tell a row that
# merely looks highlighted from one that is actually marked.
def rendered_checkboxes(list_view)
  [].tap do |ticks|
    row = list_view.first_child
    while row
      ticks << row.first_child.first_child.active?
      row = row.next_sibling
    end
  end
end

App.new(
  backend:         BACKEND,
  settings:        SETTINGS,
  app_id:          'org.gnome.ContactsRb.Drive',
  flags:           :non_unique,
  search_provider: false,
).then do |app|
  GtkDriver.drive(app, shots: 'tmp/shots') do |d, _|
    store = -> { app.instance_variable_get(:@store) }

    d.window { app.window }

    d.step('the app opens on the empty state') do
      d.check('sidebar shows the no-contacts page') do
        app.contacts_list.stack.visible_child_name == 'empty'
      end
      d.check('content pane shows nothing selected') do
        app.contact_pane.stack.visible_child_name == 'none-selected-page'
      end
      d.shot('01-empty')
    end

    d.step('add three contacts') do
      store.call.add_contact(**ADA)
      store.call.add_contact(
        name:            'Grace Hopper',
        structured_name: { given: 'Grace', family: 'Hopper' },
        emails:          [{ value: 'grace@navy.mil', type: 'Work' }],
        roles:           [{ organization: 'US Navy', title: 'Rear Admiral', type: 'Work' }],
      )
      store.call.add_contact(
        name:            'Alan Turing',
        structured_name: { given: 'Alan', family: 'Turing' },
        phones:          [{ value: '+44 161 306 6000', type: 'Mobile' }],
      )
      app.contacts_list.update_visible_page
    end

    d.step('the list fills in, favourites first') do
      d.check('three contacts') { store.call.n_contacts == 3 }
      d.check('the list page is showing') { app.contacts_list.stack.visible_child_name == 'list' }
      d.check('the favourite sorts to the top') do
        store.call.contacts.first.name == 'Ada Lovelace'
      end
      d.shot('02-list')
    end

    d.step('select the first contact') do
      store.call.select_contact(store.call.contacts.first)
    end

    d.step('the sheet shows every field') do
      d.check('the sheet page is showing') do
        app.contact_pane.stack.visible_child_name == 'contact-sheet-page'
      end
      d.check('the header buttons appear') { app.contact_sheet_buttons.get_property('visible') }
      d.check('the action bar is revealed') { app.actions_bar.reveal_child? }
      d.check('the sheet knows the contact') do
        app.contact_pane.sheet.name_label.label == 'Ada Lovelace'
      end
      d.check('the role line is filled in') do
        app.contact_pane.sheet.role_label.label == 'Mathematician at Analytical Engine Co'
      end
      d.shot('03-sheet')
    end

    d.step('open the editor') { app.window.activate_action('edit-contact', nil) }

    d.step('the editor is populated, structured name included') do
      d.check('the editor page is showing') do
        app.contact_pane.stack.visible_child_name == 'contact-editor-page'
      end
      app.contact_pane.editor.then do |editor|
        d.check('full name') { editor.name_row.text == 'Ada Lovelace' }
        d.check('given name') { editor.given_name_row.text == 'Ada' }
        d.check('family name') { editor.family_name_row.text == 'Lovelace' }
        d.check('middle name') { editor.additional_name_row.text == 'Byron' }
        d.check('title') { editor.prefixes_row.text == 'Ms' }
        d.check('suffix') { editor.suffixes_row.text == 'FRS' }
        d.check('birthday') { editor.birthday_row.text == '1815-12-10' }
      end
      d.shot('04-editor')
    end

    d.step('rename through the editor and save') do
      app.contact_pane.editor.name_row.text = 'Augusta Ada King'
      app.done_button.activate
    end

    d.step('the rename reached the model and the file') do
      d.check('the model has the new name') do
        store.call.contacts.any? { |c| c.name == 'Augusta Ada King' }
      end
      d.check('the backend has the new name') do
        BACKEND.load.any? { |c| c[:name] == 'Augusta Ada King' }
      end
      d.check('back on the sheet') do
        app.contact_pane.stack.visible_child_name == 'contact-sheet-page'
      end
      d.shot('05-after-edit')
    end

    d.step('enter selection mode') { app.window.activate_action('select-contacts', nil) }

    d.step('selection mode swaps the chrome') do
      d.check('the list is in selection mode') { app.contacts_list.selection_mode? }
      d.check('the selection header is shown') { app.selection_header.get_property('visible') }
      d.check('the normal header is hidden') { !app.left_header.get_property('visible') }
      d.check('Link is offered') { app.link_button.get_property('visible') }
      d.check('Link is disabled with nothing marked') { !app.link_button.sensitive? }
      d.shot('06-selection-mode')
    end

    d.step('mark two contacts') { store.call.multi_selection_model.select_all }

    d.step('marking enables the bulk actions') do
      d.check('the title counts them') { app.selection_title.title == '3 Selected' }
      d.check('every checkbox is ticked') do
        rendered_checkboxes(app.contacts_list.list_view).then do |ticks|
          ticks.length == 3 && ticks.all?
        end
      end
      d.check('Link is enabled') { app.link_button.sensitive? }
      d.check('Delete is enabled') { app.delete_button.sensitive? }
      d.shot('07-selection-marked')
    end

    d.step('leave selection mode') { app.window.activate_action('cancel-selection', nil) }

    d.step('search for someone') do
      app.window.activate_action('focus-search', nil)
      app.filter_entry.text = 'hopper'
    end

    d.step('the search narrows the list') do
      d.check('the search bar is open') { app.search_bar.search_mode? }
      d.check('one contact matches') { store.call.n_visible == 1 }
      d.shot('08-search')
    end

    d.step('search for nothing at all') { app.filter_entry.text = 'zzzznothing' }

    d.step('the no-results page appears') do
      d.check('no results page') { app.contacts_list.stack.visible_child_name == 'no-results' }
      d.shot('09-no-results')
    end

    d.step('clear the search') do
      app.filter_entry.text = ''
      app.search_bar.search_mode = false
    end

    d.step('sort by surname') do
      app.window.activate_action('sort-on', GLib::Variant.new('surname'))
    end

    d.step('the order and the row labels follow the surname') do
      d.check('Hopper now sorts before Turing') do
        store.call.contacts.map(&:name).then do |names|
          names.index('Grace Hopper') < names.index('Alan Turing')
        end
      end
      d.check('the setting was recorded') { SETTINGS['sort-on-surname'] }
      d.shot('10-sorted-by-surname')
    end

    d.step('back to first-name order') do
      app.window.activate_action('sort-on', GLib::Variant.new('first-name'))
    end

    d.step('share the selected contact as a QR code') do
      store.call.select_contact(store.call.contacts.first)
      app.window.activate_action('show-contact-qr-code', nil)
    end

    d.step('the QR dialog renders in the window') do
      d.check('a dialog is open') { !app.window.visible_dialog.nil? }
      d.shot('11-qr-code')
      app.window.visible_dialog&.close
    end

    d.step('open preferences') { app.app.activate_action('show-preferences', nil) }

    d.step('preferences names the address book') do
      d.check('a dialog is open') { !app.window.visible_dialog.nil? }
      d.shot('12-preferences')
      app.window.visible_dialog&.close
    end

    d.step('open the shortcuts window') { app.app.activate_action('shortcuts', nil) }

    d.step('the shortcuts dialog lists the accelerators') do
      d.check('a dialog is open') { !app.window.visible_dialog.nil? }
      d.shot('13-shortcuts')
      app.window.visible_dialog&.close
    end

    d.step('export everything, then delete a contact') do
      File.join(DIR, 'export.vcf').then do |path|
        app.send(:write_export, Gio::File.new_for_path(path), store.call.contacts)
        d.check('the export holds every contact') do
          File.read(path).scan('BEGIN:VCARD').length == 3
        end
      end

      store.call.select_contact(store.call.contacts.first)
      app.window.activate_action('delete-contact', nil)
    end

    d.step('the delete took effect and offers an undo') do
      d.check('two contacts left') { store.call.n_contacts == 2 }
      d.check('the deletion is undoable') { !app.operations.last_reversable.nil? }
      d.shot('14-after-delete')
    end

    d.step('undo the delete') { app.window.activate_action('undo-operation', nil) }

    d.step('the contact came back') do
      d.check('three contacts again') { store.call.n_contacts == 3 }
      d.check('and it is back in the file') { BACKEND.load.length == 3 }
      d.shot('15-after-undo')
    end

    d.step('import a vCard written by something else') do
      File.join(DIR, 'import.vcf').then do |path|
        File.write(path, <<~VCF)
          BEGIN:VCARD
          VERSION:3.0
          N:Babbage;Charles;;;
          item1.EMAIL;type=INTERNET;type=pref:charles@difference.engine
          TEL;TYPE="VOICE,WORK":+44 20 7946 0300
          ADR;TYPE=WORK:;;1 Dorset Street;London;;W1;UK
          BDAY:17911226
          END:VCARD
        VCF
        app.send(:import_parsed, VCard.parse_all(File.read(path)))
      end
    end

    d.step('the imported contact arrived intact') do
      store.call.contacts.find { |c| c.name.include?('Babbage') }.then do |charles|
        d.check('the contact exists') { !charles.nil? }
        d.check('the name came from N') { charles&.name == 'Charles Babbage' }
        d.check('the grouped email survived') do
          charles&.emails&.first&.value == 'charles@difference.engine'
        end
        d.check('the quoted phone type resolved') { charles&.phones&.first&.type == 'Work' }
        d.check('the address components joined') do
          charles&.addresses&.first&.value == '1 Dorset Street, London, W1, UK'
        end
        d.check('the birthday parsed') { charles&.birthday == Date.new(1791, 12, 26) }
      end
      d.shot('16-after-import')
    end

    d.step('everything survives a reload from disk') do
      ContactStore.new(backend: Backends::JsonBackend.new(path: File.join(DIR, 'contacts.json'))).then do |fresh|
        fresh.load
        d.check('four contacts on disk') { fresh.n_contacts == 4 }
        fresh.contacts.find { |c| c.name == 'Augusta Ada King' }.then do |ada|
          d.check('the edited name persisted') { !ada.nil? }
          d.check('the structured name persisted') { ada&.structured_name&.family == 'Lovelace' }
          d.check('the IM addresses persisted') { ada&.im_addresses&.length == 2 }
          d.check('the custom phone type persisted') do
            ada&.phones&.map(&:type)&.include?('Work Fax')
          end
          d.check('the favourite flag persisted') { ada&.favorite? }
        end
      end
    end
  end
end
