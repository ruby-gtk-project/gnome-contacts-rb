# frozen_string_literal: true

require 'adwaita'
require_relative 'contact_sheet'
require_relative 'contact_editor'

# ContactPane is the right pane showing contact details.
#
# Converted from GNOME Contacts contact-pane.vala and contacts-contact-pane.blp
#
# Structure:
#   Adwaita::Bin
#     └── Gtk::Stack
#           ├── none-selected-page (Adwaita::StatusPage)
#           ├── contact-sheet-page (ScrolledWindow → Adwaita::Clamp → ContactSheet)
#           └── contact-editor-page (ScrolledWindow → Adwaita::Clamp → ContactEditor)
#
class ContactPane < Adwaita::Bin
  attr_reader :on_edit_mode

  def initialize(store, on_save_callback)
    super()
    @store = store
    @on_save = on_save_callback
    @contact = nil
    @on_edit_mode = false
    @sheet = nil
    @editor = nil
  end

  def build
    self.tap do |pane|
      pane.hexpand = true
      pane.vexpand = true
      pane.child = stack

      stack.tap do |s|
        s.add_named(none_selected_page, 'none-selected-page')
        s.add_named(contact_sheet_page, 'contact-sheet-page')
        s.add_named(contact_editor_page, 'contact-editor-page')
        s.visible_child_name = 'none-selected-page'

        contact_sheet_page.tap do |csp|
          csp.child = contact_sheet_clamp
        end

        contact_editor_page.tap do |cep|
          cep.child = contact_editor_clamp

          contact_editor_clamp.tap do |cec|
            cec.child = contact_editor_box
          end
        end
      end
    end
  end

  def show_contact(contact)
    @contact = contact
    contact.then do |c|
      if c
        show_contact_sheet(c)
      else
        remove_contact_sheet
        stack.visible_child_name = 'none-selected-page'
      end
    end
  end

  def edit_contact
    @contact.then do |contact|
      if contact && !@on_edit_mode
        @on_edit_mode = true
        create_contact_editor
        stack.visible_child_name = 'contact-editor-page'
      end
    end
  end

  def new_contact
    @contact = nil
    @on_edit_mode = true
    create_contact_editor
    stack.visible_child_name = 'contact-editor-page'
  end

  def stop_editing(cancel: false)
    @on_edit_mode.then do |editing|
      if editing
        @on_edit_mode = false

        if cancel
          remove_contact_editor
          @contact.then do |c|
            stack.visible_child_name = c ? 'contact-sheet-page' : 'none-selected-page'
          end
        else
          @editor.then do |editor|
            if editor
              editor.collect_data.tap do |data|
                @on_save.call(data)
              end
            end
          end
          remove_contact_editor
        end
      end
    end
  end

  # Memoized widget methods with styles

  def stack = @stack ||= Gtk::Stack.new

  def none_selected_page
    @none_selected_page ||= Adwaita::StatusPage.new.tap do |sp|
      sp.icon_name = 'avatar-default-symbolic'
      sp.title = 'Select a Contact'
    end
  end

  def contact_sheet_page
    @contact_sheet_page ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.hscrollbar_policy = :never
      sw.vscrollbar_policy = :automatic
      sw.hexpand = true
      sw.vexpand = true
    end
  end

  def contact_sheet_clamp
    @contact_sheet_clamp ||= Adwaita::Clamp.new.tap do |c|
      c.maximum_size = 500
      c.add_css_class('contacts-sheet-container')
    end
  end

  def contact_editor_page
    @contact_editor_page ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.hscrollbar_policy = :never
      sw.vscrollbar_policy = :automatic
      sw.hexpand = true
      sw.vexpand = true
    end
  end

  def contact_editor_clamp
    @contact_editor_clamp ||= Adwaita::Clamp.new.tap do |c|
      c.maximum_size = 500
      c.add_css_class('contacts-contact-editor-container')
    end
  end

  def contact_editor_box = @contact_editor_box ||= Gtk::Box.new(:vertical, 0)

  private

  def show_contact_sheet(contact)
    remove_contact_sheet

    ContactSheet.new(contact).tap do |sheet|
      @sheet = sheet
      contact_sheet_clamp.child = sheet.build
    end

    stack.visible_child_name = 'contact-sheet-page'
  end

  def remove_contact_sheet
    @sheet.then do |sheet|
      if sheet
        contact_sheet_clamp.child = nil
        @sheet = nil
      end
    end
  end

  def create_contact_editor
    remove_contact_editor

    ContactEditor.new(contact: @contact).tap do |editor|
      @editor = editor
      contact_editor_box.append(editor.build)
    end
  end

  def remove_contact_editor
    @editor.then do |editor|
      if editor
        contact_editor_box.remove(editor.container)
        @editor = nil
      end
    end
  end
end
