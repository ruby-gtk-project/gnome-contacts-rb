# frozen_string_literal: true

require 'adwaita'
require_relative 'contact_sheet'
require_relative 'contact_editor'
require_relative 'link_suggestion_grid'

# ContactPane is the right-hand pane showing contact details.
#
# Ported from upstream's src/contacts-contact-pane.vala and
# data/ui/contacts-contact-pane.blp:
#
#   Adwaita::Bin
#     └── Gtk::Stack
#           ├── none-selected-page  (Adwaita::StatusPage)
#           ├── contact-sheet-page  (ScrolledWindow → Clamp → ContactSheet)
#           └── contact-editor-page (ScrolledWindow → Clamp → ContactEditor)
#
# The sheet and the editor are rebuilt per contact rather than updated in
# place, because the number of rows depends on how many values a contact has.
#
class ContactPane < Adwaita::Bin
  attr_reader :editor, :sheet

  def initialize(store, on_save_callback, on_link: nil, on_reject: nil)
    super()
    self.hexpand = true
    self.vexpand = true
    @store = store
    @on_save = on_save_callback
    @on_link = on_link
    @on_reject = on_reject
    @suggestion_grids = []
    @contact = nil
    @editing = false
    @sheet = nil
    @editor = nil
  end

  def build
    tap do |pane|
      pane.child = stack

      stack.tap do |s|
        s.add_named(none_selected_page, 'none-selected-page')
        s.add_named(contact_sheet_page, 'contact-sheet-page')
        s.add_named(contact_editor_page, 'contact-editor-page')
        s.visible_child_name = 'none-selected-page'

        contact_sheet_page.tap do |csp|
          csp.child = sheet_box

          sheet_box.tap do |sb|
            sb.append(contact_sheet_clamp)
            sb.append(suggestions_box)
          end
        end

        contact_editor_page.tap do |cep|
          cep.child = contact_editor_clamp

          contact_editor_clamp.child = contact_editor_box
        end
      end
    end
  end

  def editing? = @editing

  # suggestions are other contacts that look like the same person; each gets a
  # LinkSuggestionGrid under the sheet, as upstream does.
  def show_contact(contact, suggestions: [])
    @contact = contact
    remove_contact_sheet
    remove_suggestions

    contact.then do |c|
      if c
        ContactSheet.new(c).tap { |s| @sheet = s; contact_sheet_clamp.child = s.build }
        add_suggestions(suggestions)
        stack.visible_child_name = 'contact-sheet-page'
        scroll_to_top(contact_sheet_page)
      else
        stack.visible_child_name = 'none-selected-page'
      end
    end
  end

  def edit_contact
    @contact.then do |contact|
      if contact && !@editing
        @editing = true
        open_editor(contact)
      end
    end
  end

  def new_contact
    @contact = nil
    @editing = true
    open_editor(nil)
  end

  # Leaves edit mode. Unless cancelled, the editor's data is handed to the
  # save callback first. Either way the pane falls back to whatever the store
  # currently has selected, so cancelling a brand-new contact returns to the
  # previously selected one rather than to an empty pane.
  def stop_editing(cancel: false)
    @editing.then do |was_editing|
      if was_editing
        @editing = false
        unless cancel
          @editor.collect_data.then { |data| @on_save.call(data) }
        end
        remove_contact_editor
        if cancel
          show_contact(@store.selected_contact)
        end
      end
    end
  end

  # Memoized widget methods

  def stack = @stack ||= Gtk::Stack.new

  def none_selected_page
    @none_selected_page ||= Adwaita::StatusPage.new.tap do |sp|
      sp.icon_name = 'avatar-default-symbolic'
      sp.title = 'Select a Contact'
      sp.description = 'Choose someone from the list, or add a new contact'
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
      c.maximum_size = 520
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
      c.maximum_size = 520
      c.add_css_class('contacts-contact-editor-container')
    end
  end

  def contact_editor_box = @contact_editor_box ||= Gtk::Box.new(:vertical, 0)
  def sheet_box = @sheet_box ||= Gtk::Box.new(:vertical, 0)

  def suggestions_box
    @suggestions_box ||= Adwaita::Clamp.new.tap do |c|
      c.maximum_size = 520
    end
  end

  private

    def open_editor(contact)
      remove_contact_editor

      ContactEditor.new(contact: contact).tap do |ed|
        @editor = ed
        contact_editor_box.append(ed.build)
      end

      stack.visible_child_name = 'contact-editor-page'
      scroll_to_top(contact_editor_page)
    end

  # A newly shown contact starts at the top of its sheet, rather than
  # inheriting the scroll position of whoever was selected before.
  #
  # Deferred to an idle tick on purpose: at the moment the child is swapped in
  # the scrolled window has not allocated it yet, and GTK then scrolls to
  # whichever selectable label takes focus — which lands the sheet at the
  # bottom. Resetting after layout wins that race.
    def scroll_to_top(scroller)
      GLib::Idle.add do
        scroller.vadjustment.value = scroller.vadjustment.lower
        false
      end
    end

  # Upstream shows one suggestion at a time; showing the strongest match keeps
  # the sheet from turning into a wall of prompts.
    def add_suggestions(suggestions)
      Array(suggestions).first.then do |suggestion|
        if suggestion && @on_link
          LinkSuggestionGrid.new(suggestion, @on_link, @on_reject).tap do |grid|
            @suggestion_grids << grid
            suggestions_box.child = grid.build
          end
        end
      end
    end

    def remove_suggestions
      suggestions_box.child = nil
      @suggestion_grids.clear
    end

    def remove_contact_sheet
      @sheet.then do |sheet|
        if sheet
          contact_sheet_clamp.child = nil
          @sheet = nil
        end
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
