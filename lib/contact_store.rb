# frozen_string_literal: true

require 'gtk4'
require 'securerandom'
require_relative 'contact'
require_relative 'backend'
require_relative 'json_backend'
require_relative 'vcard_backend'

# ContactStore is the data layer for the contacts application.
#
# It owns the backend, the Gio::ListStore holding every Contact, and the
# filter/sort/selection chain the sidebar list view binds to:
#
#   ListStore (kept sorted) -> FilterListModel -> SingleSelection
#
class ContactStore
  MULTI_VALUE_FIELDS = %i[emails phones urls addresses notes].freeze
  CONTACT_FIELDS = (%i[name nickname birthday favorite roles] + MULTI_VALUE_FIELDS).freeze

  attr_reader :backend, :list_store

  def initialize(backend: nil)
    @backend = backend || Backends::JsonBackend.new
    @list_store = Gio::ListStore.new(Contact)
    @query = ''
  end

  def load
    @backend.load.each { |hash| @list_store.append(Contact.from_h(hash)) }
    resort
  end

  def query = @query

  def query=(value)
    @query = value.to_s.downcase
    contact_filter.changed(Gtk::FilterChange::DIFFERENT)
  end

  def contact_filter
    @contact_filter ||= Gtk::CustomFilter.new do |item|
      @query.empty? || matches_query?(item, @query)
    end
  end

  def filter_model = @filter_model ||= Gtk::FilterListModel.new(@list_store, contact_filter)
  def selection_model = @selection_model ||= Gtk::SingleSelection.new(filter_model)

  # The visible, ordered model the sidebar binds to. Ordering is maintained in
  # the backing list store rather than by a Gtk::SortListModel — see #resort.
  def sorted_model = filter_model

  def n_contacts = @list_store.n_items
  def n_visible = filter_model.n_items
  def empty? = n_contacts.zero?

  def add_contact(**attributes)
    Contact.from_h(normalize(attributes).merge(id: attributes[:id] || SecureRandom.uuid)).tap do |contact|
      @backend.create(contact.to_h)
      @list_store.append(contact)
      resort
    end
  end

  def update_contact(contact, **attributes)
    contact.tap do |c|
      normalize(attributes).tap do |normalized|
        CONTACT_FIELDS.each do |field|
          c.public_send(:"#{field}=", normalized[field]) if normalized.key?(field)
        end
      end
      @backend.update(c.to_h)
      refresh(c)
    end
  end

  def delete_contact(contact)
    find_position(contact).then do |position|
      if position
        @backend.delete(contact.id)
        @list_store.remove(position)
        { position: position, contact: contact }
      end
    end
  end

  def restore_contact(undo_info)
    undo_info[:contact].tap do |contact|
      @backend.create(contact.to_h)
      @list_store.insert(undo_info[:position], contact)
      resort
    end
  end

  # Imports a batch of contact hashes, skipping any whose id already exists.
  # Returns the contacts that were actually added.
  def import(hashes)
    hashes.reject { |hash| known_id?(hash[:id] || hash['id']) }
          .map { |hash| add_contact(**Contact.from_h(hash).to_h) }
  end

  def contacts = (0...@list_store.n_items).map { |i| @list_store.get_item(i) }

  def select_contact(contact)
    position_in_view(contact).then do |index|
      selection_model.selected = index if index
      !index.nil?
    end
  end

  def selected_contact = selection_model.selected_item

  def toggle_favorite(contact) = set_favorite(contact, !contact.favorite?)

  def set_favorite(contact, value)
    contact.tap do |c|
      c.favorite = value
      @backend.update(c.to_h)
      refresh(c)
    end
  end

  private

  # Coerces plain hashes coming from the editor or a backend into the
  # TypedValue/Role objects Contact stores. Values that are already coerced
  # pass through untouched, so normalising twice is harmless.
  def normalize(attributes)
    attributes.dup.tap do |result|
      MULTI_VALUE_FIELDS.each do |field|
        result[field] = Array(result[field]).map { |v| TypedValue.coerce(v) } if result.key?(field)
      end
      result[:roles] = Array(result[:roles]).map { |v| Role.coerce(v) } if result.key?(:roles)
      result[:birthday] = Contact.parse_birthday(result[:birthday]) if result.key?(:birthday)
    end
  end

  # Gio::ListStore has no "this item changed" signal, so re-emitting
  # items-changed for the contact's row is what makes the list view rebind it.
  def refresh(contact)
    find_position(contact).then do |position|
      @list_store.items_changed(position, 1, 1) if position
    end
    contact_filter.changed(Gtk::FilterChange::DIFFERENT)
    resort
  end

  # Favourites float to the top; everything else is ordered by display name.
  #
  # This deliberately avoids Gtk::CustomSorter/Gio::ListStore#sort: in
  # ruby-gnome 4.3.7 those hand the comparison block raw GObject pointers as
  # Integers rather than the Ruby objects, so any comparison on the contact
  # raises NoMethodError. Gtk::CustomFilter does not share the bug, and
  # Gio::ListStore#splice round-trips the objects intact, so we sort in Ruby
  # and splice the result back.
  def resort
    selected_contact.then do |previously_selected|
      contacts.sort_by { |c| [c.favorite? ? 0 : 1, c.display_name.downcase, c.id.to_s] }.then do |sorted|
        @list_store.splice(0, @list_store.n_items, sorted) unless sorted == contacts
      end
      restore_selection(previously_selected)
    end
  end

  # Splicing resets the selection model, so put the cursor back where it was.
  def restore_selection(contact)
    contact.then do |target|
      position_in_view(target).then do |index|
        selection_model.selected = index if target && index
      end
    end
  end

  def position_in_view(contact)
    contact.then do |target|
      (0...filter_model.n_items).find { |i| filter_model.get_item(i).id == target.id } if target
    end
  end

  def known_id?(id) = !id.nil? && (0...@list_store.n_items).any? { |i| @list_store.get_item(i).id == id }

  def matches_query?(item, query)
    searchable_fields(item).any? { |field| field.to_s.downcase.include?(query) }
  end

  def searchable_fields(item)
    [
      item.name,
      item.nickname,
      item.emails.map(&:value),
      item.phones.map(&:value),
      item.addresses.map(&:value),
      item.roles.map { |r| [r.organization, r.title] },
      item.notes.map(&:value)
    ].flatten
  end

  def find_position(contact)
    (0...@list_store.n_items).find { |i| @list_store.get_item(i).id == contact.id }
  end
end
