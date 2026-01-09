# frozen_string_literal: true

require 'gtk4'
require 'securerandom'
require_relative 'contact'
require_relative 'backend'
require_relative 'json_backend'
require_relative 'vcard_backend'

# ContactStore is the data layer for the contacts application.
#
class ContactStore
  attr_reader :backend, :list_store

  def initialize(backend: nil)
    @backend = backend || Backends::JsonBackend.new
    @list_store = Gio::ListStore.new(Contact)
    @query = ''
  end

  def load
    @backend.load.each { |hash| @list_store.append(Contact.from_h(hash)) }
  end

  def query = @query

  def query=(value)
    @query = value.to_s.downcase
    contact_filter.changed(Gtk::FilterChange::DIFFERENT)
  end

  def filter_model
    @filter_model ||= Gtk::FilterListModel.new(@list_store, contact_filter)
  end

  def selection_model
    @selection_model ||= Gtk::SingleSelection.new(filter_model)
  end

  def contact_filter
    @contact_filter ||= Gtk::CustomFilter.new do |item|
      @query.empty? || matches_query?(item, @query)
    end
  end

  def add_contact(**attributes)
    # Convert hash arrays to TypedValue/Role objects
    normalized = normalize_attributes(attributes)
    Contact.from_h(normalized.merge(id: normalized[:id] || SecureRandom.uuid)).tap do |contact|
      @backend.create(contact.to_h)
      @list_store.append(contact)
    end
  end

  def update_contact(contact, **attributes)
    normalized = normalize_attributes(attributes)
    contact.tap do |c|
      CONTACT_FIELDS.each do |field|
        c.send("#{field}=", normalized[field]) if normalized.key?(field)
      end
      @backend.update(c.to_h)
      contact_filter.changed(Gtk::FilterChange::DIFFERENT)
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
    end
  end

  def select_contact(contact)
    (0...filter_model.n_items).find { |i| filter_model.get_item(i).id == contact.id }.then do |index|
      selection_model.selected = index if index
      !index.nil?
    end
  end

  def selected_contact
    selection_model.selected_item
  end

  def toggle_favorite(contact)
    contact.tap do |c|
      c.favorite = !c.favorite?
      @backend.update(c.to_h)
    end
  end

  def set_favorite(contact, value)
    contact.tap do |c|
      c.favorite = value
      @backend.update(c.to_h)
    end
  end

  private

  CONTACT_FIELDS = %i[name nickname birthday favorite emails phones urls addresses notes roles].freeze

  def normalize_attributes(attributes)
    attributes.transform_values.with_index do |value, _|
      value
    end.to_h.tap do |result|
      # Convert email/phone/etc hashes to TypedValue objects
      %i[emails phones urls addresses notes].each do |field|
        result[field] = (result[field] || []).map do |v|
          v.is_a?(Hash) ? TypedValue.from_h(v) : v
        end if result.key?(field)
      end

      # Convert roles hashes to Role objects
      result[:roles] = (result[:roles] || []).map do |v|
        v.is_a?(Hash) ? Role.from_h(v) : v
      end if result.key?(:roles)
    end
  end

  def matches_query?(item, query)
    searchable_fields(item).any? { |field| field.to_s.downcase.include?(query) }
  end

  def searchable_fields(item)
    [
      item.name,
      item.nickname,
      item.emails.map(&:value),
      item.phones.map(&:value),
      item.roles.map { |r| [r.organization, r.title] },
      item.notes.map(&:value)
    ].flatten
  end

  def find_position(contact)
    (0...@list_store.n_items).find { |i| @list_store.get_item(i).id == contact.id }
  end
end
