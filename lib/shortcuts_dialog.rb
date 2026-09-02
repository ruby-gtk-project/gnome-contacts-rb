# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# A direct port of upstream's data/ui/contacts-shortcuts-dialog.blp, which is
# an Adw.ShortcutsDialog with an Overview section and an "Editing or creating a
# contact" section. The items below are the same ones, with the accelerators
# this port actually binds.
#
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'Overview'                      => [
      ['Show help', 'F1'],
      ['Open menu', 'F10'],
      ['Show preferences', '<Control>comma'],
      ['Create a new contact', '<Control>n'],
      ['Search contacts', '<Control>f'],
      ['Import from file', '<Control>i'],
      ['Export all contacts', '<Control><Shift>e'],
      ['Delete contact', 'Delete'],
      ['Shortcut list', '<Control>question'],
      ['Quit', '<Control>q']
    ],
    'Editing or creating a contact' => [
      ['Save current changes to contact', '<Control>Return'],
      ['Cancel current changes for contact', 'Escape']
    ],
  }.freeze

  def initialize
    super()
    self.title = 'Keyboard Shortcuts'
  end

  def build
    tap do |dialog|
      SECTIONS.each do |title, items|
        dialog.add(section(title, items))
      end
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

  # Positional, not keyword, arguments — even though the error a no-argument
  # new raises advertises the signatures as "title: utf8, accelerator: utf8".
  # Passing them as keywords fails; passing them positionally works.
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
