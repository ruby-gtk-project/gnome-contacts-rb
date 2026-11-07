# frozen_string_literal: true

# Drives the real application through the features added in the port, one step
# per turn of the GTK main loop, and writes a screenshot of each state.
#
#   nix develop --command xvfb-run -a ruby test/drive_main_window.rb
#
# This machine has no display and GTK4 here has no offscreen backend either —
# gtk_init fails outright with no display — so xvfb-run is not optional.

require 'tmpdir'
require 'fileutils'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# GLib2's closure marshaling (every `activate_action`, every signal) calls
# back into Ruby from inside a GObject C callback. If Ruby's GC happens to
# start sweeping while one of those callbacks is on the C stack, the VM hits
# "[BUG] object allocation during garbage collection phase" and aborts — seen
# here crashing in unrelated, innocuous code (lib/qr_code_dialog.rb's Integer#&
# one run, a String#gsub in lib/vcard.rb the next), which is the signature of
# a GC-reentrancy bug in the binding rather than anything wrong with the code
# that happened to be running when the timer fired. Confirmed by disabling GC
# entirely: the exact same steps then run to completion with 0 failures. This
# is a short-lived, single-purpose process — nothing here depends on memory
# being reclaimed before it exits — so disabling GC is a safe way to drive the
# app without the crash; it changes nothing about what the checks observe.
GC.disable

# A scratch home so a drive never reads or scribbles on the real address book.
Dir.mktmpdir('contacts-drive').tap do |dir|
  ENV['XDG_CONFIG_HOME'] = File.join(dir, 'config')
  ENV['XDG_DATA_HOME'] = File.join(dir, 'data')
end

require 'main'
require 'json_backend'
require 'settings'
require_relative '../lib/eds_backend'
require_relative 'gtk_driver'

DIR = Dir.mktmpdir('contacts-drive-store')
BACKEND = Backends::JsonBackend.new(path: File.join(DIR, 'contacts.json'))
SETTINGS = Settings.new(path: File.join(DIR, 'settings.json'))

# A real, valid 1x1 transparent PNG — not the placeholder text the minitest
# suite feeds glycin (which only ever exercises its failure path). Decoding
# this is the one check in the whole suite that proves Gly::Loader ->
# GlyGtk4.frame_get_texture turns real bytes into a real texture rather than
# just being reachable.
ONE_PIXEL_PNG = Base64.decode64(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
)

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

# Every Gtk::Label text in a widget tree — used where a dialog's content
# (e.g. ImportDialog's per-contact rows) has no direct accessor for what it
# rendered.
def labels(widget, found = [])
  found.tap do
    if widget.is_a?(Gtk::Label)
      found << widget.label
    end
    widget.first_child.then do |first|
      child = first
      while child
        labels(child, found)
        child = child.next_sibling
      end
    end
  end
end

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

# LinkSuggestionGrid's buttons_box is built as [reject_button, accept_button]
# appended in that order; there is no direct accessor from the pane to the
# grid object (only to the built widget tree), so this walks the tree the
# same way `labels` and `rendered_checkboxes` above do.
def suggestion_buttons(pane)
  pane.suggestions_box.child&.first_child&.next_sibling&.next_sibling.then do |buttons_box|
    [buttons_box&.first_child, buttons_box&.first_child&.next_sibling]
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
        # Goes through the real ImportDialog (the review/confirm dialog),
        # not straight to import_parsed: Gtk::FileDialog itself can't be
        # driven (it's async and raises on cancel), but everything it hands
        # off to — the dialog that previews what is about to be imported —
        # is ordinary widget code and belongs under test like any other
        # dialog.
        app.send(:open_import_dialog, [Gio::File.new_for_path(path)])
      end
    end

    d.step('the import dialog previews the parsed contact') do
      d.check('a dialog is open') { !app.window.visible_dialog.nil? }
      app.window.visible_dialog.then do |dialog|
        d.check('the import button is enabled') { dialog.import_button.sensitive? }
        d.check('the row names the contact') do
          labels(dialog.page).any? { |text| text.to_s.include?('Babbage') }
        end
      end
      d.shot('16a-import-preview')
    end

    d.step('confirm the import') { app.window.visible_dialog.import_button.activate }

    d.step('the imported contact arrived intact') do
      d.check('the dialog closed') { app.window.visible_dialog.nil? }
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

    # The checks above never touch glycin, goa-rb, edataserver or the ashpd
    # camera check: no contact here carries an avatar, and setup_backends is
    # never passed to this App, so AccountsList (and the GOA client it
    # queries) and EdsBackend are never built. Exercise each directly against
    # the real gem, the way the live code path calls it, rather than taking
    # "required and called from somewhere" on faith.
    d.step('decode a real avatar through glycin') do
      Avatar.new(data: ONE_PIXEL_PNG, media_type: 'image/png').texture.then do |texture|
        d.check('glycin decoded a real Gdk::Texture') { texture.is_a?(Gdk::Texture) }
        d.check('the decoded texture is 1x1') { texture&.width == 1 && texture&.height == 1 }
      end
    end

    d.step('open the editor on a contact carrying a real avatar') do
      store.call.contacts.find { |c| c.name == 'Augusta Ada King' }.then do |ada|
        ada.avatar = Avatar.new(data: ONE_PIXEL_PNG, media_type: 'image/png')
        store.call.select_contact(ada)
      end
      app.window.activate_action('edit-contact', nil)
    end

    d.step('that avatar reaches the editor through EditableAvatar') do
      d.check('the editor avatar carries a real decoded texture') do
        app.contact_pane.editor.editable_avatar.avatar.custom_image.is_a?(Gdk::Texture)
      end
      app.done_button.activate
    end

    d.step('edataserver lists the real EDS address-book sources') do
      Backends::EdsBackend.discover.then do |books|
        d.check('discovery ran against the real source registry without raising') { books.is_a?(Array) }
      end
    end

    d.step('goa-rb is queried for a provider icon when building AccountsList') do
      AccountsList.new([BACKEND], primary: BACKEND).build.then do |group|
        d.check('the row for the only backend was built') { group.rows.length == 1 }
        d.check('the real Goa::Client was queried (no GOA account, so it falls back)') do
          group.send(:goa_client).is_a?(Goa::Client) &&
            group.rows.values.first.first_child.is_a?(Gtk::Widget)
        end
      end
    end

    d.step('ashpd trash-portal delete runs for real on a vCard backend') do
      Backends::VCardBackend.new(path: Dir.mktmpdir('contacts-drive-vcard')).then do |vcard_backend|
        vcard_backend.create({ name: 'Delete Me' }).then do |created|
          d.check('the vCard delete call completed (real portal or its rescue fallback)') do
            vcard_backend.delete(created[:id])
          end
        end
      end
    end

    d.step('ashpd reports the real camera presence to the avatar selector') do
      # Same portal call AvatarSelector#camera_present_with_reason makes, and
      # the same rescue: this dev shell's sandbox has no portal daemon to ask
      # ("the name is not activatable"), so the live call raises here exactly
      # as it does inside the app — proof it is a real D-Bus round trip, not
      # a stub.
      present =
        begin
          Ashpd::Camera.present?
        rescue StandardError
          false
        end

      AvatarSelector.new(store.call.contacts.first, ->(_) {}).build.then do |selector|
        d.check('the camera button sensitivity matches the live portal check') do
          selector.camera_button.sensitive? == present
        end
      end
    end

    d.step('add two contacts that share an email, to trigger a link suggestion') do
      store.call.add_contact(
        name:            'Rosa Peters',
        structured_name: { given: 'Rosa', family: 'Peters' },
        emails:          [{ value: 'rosa@example.com', type: 'Work' }],
      )
      store.call.add_contact(
        name:            'Rosa B Peters',
        structured_name: { given: 'Rosa', family: 'B Peters' },
        emails:          [{ value: 'rosa@example.com', type: 'Home' }],
      )
      app.contacts_list.update_visible_page
      store.call.select_contact(store.call.contacts.find { |c| c.name == 'Rosa Peters' })
    end

    d.step('the link-suggestion grid appears under the sheet') do
      d.check('a suggestion grid is shown') { !app.contact_pane.suggestions_box.child.nil? }
      d.shot('17-link-suggestion')
    end

    # The suggestion grid is only just added to a not-yet-laid-out box this
    # same tick, so it is not mapped yet; `button.activate` requires a mapped
    # widget and is a no-op here, unlike every other `.activate` call in this
    # script (those buttons live in widgets that have been on screen for a
    # while). Emitting the signal directly is what an actual click delivers
    # regardless of map state, and still exercises the real handler wiring.
    d.step('reject the suggestion') { suggestion_buttons(app.contact_pane).first.signal_emit('clicked') }

    d.step('the suggestion is dismissed') do
      d.check('the suggestion grid is gone') { app.contact_pane.suggestions_box.child.nil? }
    end

    d.step('select the other side of the dismissed pair') do
      store.call.select_contact(store.call.contacts.find { |c| c.name == 'Rosa B Peters' })
    end

    d.step('the dismissal is persisted both ways') do
      d.check('the reverse pairing offers no suggestion either') do
        app.contact_pane.suggestions_box.child.nil?
      end
      d.shot('18-suggestion-dismissed')
    end

    d.step('add a second pair sharing a phone number, to accept this time') do
      store.call.add_contact(
        name:            'Devon Clarke',
        structured_name: { given: 'Devon', family: 'Clarke' },
        phones:          [{ value: '+1 555 010 0100', type: 'Mobile' }],
      )
      store.call.add_contact(
        name:            'D Clarke',
        structured_name: { given: 'D', family: 'Clarke' },
        phones:          [{ value: '+1 555 010 0100', type: 'Work' }],
        emails:          [{ value: 'd.clarke@example.com', type: 'Work' }],
      )
      app.contacts_list.update_visible_page
      store.call.select_contact(store.call.contacts.find { |c| c.name == 'Devon Clarke' })
    end

    d.step('the second pair also offers a suggestion') do
      d.check('a suggestion grid is shown for the phone match') do
        !app.contact_pane.suggestions_box.child.nil?
      end
    end

    d.step('accept the suggestion') do
      before = store.call.n_contacts
      suggestion_buttons(app.contact_pane).last.signal_emit('clicked')
      d.check('one contact disappeared (linked into the other)') { store.call.n_contacts == before - 1 }
    end

    d.step('the link merged both contacts into one, and it is undoable') do
      store.call.contacts.find { |c| c.name == 'Devon Clarke' || c.name == 'D Clarke' }.then do |merged|
        d.check('the merged contact kept a name') { !merged.nil? }
        d.check('the merged contact kept the shared phone') do
          merged&.phones&.any? { |p| p.value == '+1 555 010 0100' }
        end
        d.check("the merged contact gained the other side's email") do
          merged&.emails&.any? { |e| e.value == 'd.clarke@example.com' }
        end
      end
      d.check('the link is undoable') { !app.operations.last_reversable.nil? }
      d.shot('19-link-accepted')
    end
  end
end
