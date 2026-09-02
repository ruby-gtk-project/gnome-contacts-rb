# frozen_string_literal: true

require 'gtk4'
require 'securerandom'
require 'set'
require_relative 'contact'
require_relative 'backend'
require_relative 'json_backend'
require_relative 'vcard_backend'

# ContactStore is the data layer for the contacts application.
#
# It owns the backend, the Gio::ListStore the sidebar binds to, and the
# filter/selection chain on top of it:
#
#   ListStore (kept sorted) -> FilterListModel -> SingleSelection
#
# It also keeps its own ordered Array holding the same contacts, and that Array
# — not the list store — is what every read goes through.
#
# The reason is memory safety. Removing an item from a Gio::ListStore drops the
# reference keeping it alive, and a Ruby wrapper GTK hands back afterwards can
# point at freed memory; touching it segfaults rather than raising. Keeping a
# strong Ruby-side reference to every live contact, and never reading a Contact
# back out of a GTK model, removes that whole class of crash. The models still
# drive the view; they are just not the source of truth.
#
class ContactStore
  MULTI_VALUE_FIELDS = Contact::MULTI_VALUE_FIELDS
  CONTACT_FIELDS = Contact::ALL_FIELDS

  # GTK reports "nothing selected" as GTK_INVALID_LIST_POSITION, which arrives
  # as a very large unsigned integer rather than nil.
  INVALID_POSITION = 0xFFFFFFFF

  attr_reader :backend, :list_store
  attr_accessor :sort_on_surname

  def initialize(backend: nil, sort_on_surname: false)
    @backend = backend || Backends::JsonBackend.new
    @list_store = Gio::ListStore.new(Contact)
    @ordered = []
    @query = ''
    @sort_on_surname = sort_on_surname
  end

  def load
    @backend.load.each do |hash|
      Contact.from_h(hash).tap do |contact|
        @ordered << contact
        @list_store.append(contact)
      end
    end
    resort
  end

  # --- Models the view binds to -------------------------------------------

  def contact_filter
    @contact_filter ||= Gtk::CustomFilter.new do |item|
      @query.empty? || matches_query?(item, @query)
    end
  end

  def filter_model = @filter_model ||= Gtk::FilterListModel.new(@list_store, contact_filter)
  def selection_model = @selection_model ||= Gtk::SingleSelection.new(filter_model)

  # The sidebar swaps in a Gtk::MultiSelection for selection mode, which is how
  # upstream's main window drives "export / link / delete marked contacts".
  def multi_selection_model = @multi_selection_model ||= Gtk::MultiSelection.new(filter_model)

  # The visible, ordered model the sidebar binds to. Ordering is maintained in
  # the backing list store rather than by a Gtk::SortListModel — see #resort.
  def sorted_model = filter_model

  # --- Reading ------------------------------------------------------------

  def query = @query

  def query=(value)
    @query = value.to_s.downcase
    contact_filter.changed(Gtk::FilterChange::DIFFERENT)
  end

  # Every contact, in sidebar order.
  def contacts = @ordered.dup

  # The contacts the current search leaves showing, in the order the filter
  # model presents them, so a model index is an index into this.
  def visible_contacts
    @ordered.select do |contact|
      @query.empty? || matches_query?(contact, @query)
    end
  end

  def n_contacts = @ordered.length
  def n_visible = visible_contacts.length
  def empty? = @ordered.empty?

  # Resolved through our own array rather than selection_model.selected_item,
  # which can hand back a wrapper for an item the store has already dropped.
  def selected_contact
    valid_index(selection_model.selected).then do |index|
      if index
        visible_contacts[index]
      end
    end
  end

  def marked_contacts
    visible_contacts.then do |visible|
      (0...visible.length).select { |i| multi_selection_model.selected?(i) }
                          .map { |i| visible[i] }
    end
  end

  def unmark_all = multi_selection_model.unselect_all

  def select_contact(contact)
    position_in_view(contact).then do |index|
      if index
        selection_model.selected = index
      end
      !index.nil?
    end
  end

  # --- Writing ------------------------------------------------------------

  def add_contact(**attributes)
    Contact.from_h(normalize(attributes).merge(id: attributes[:id] || SecureRandom.uuid)).tap do |contact|
      @backend.create(contact.to_h)
      @ordered << contact
      @list_store.append(contact)
      resort
    end
  end

  def update_contact(contact, **attributes)
    contact.tap do |c|
      normalize(attributes).tap do |normalized|
        CONTACT_FIELDS.each do |field|
          if normalized.key?(field)
            c.public_send(:"#{field}=", normalized[field])
          end
        end
      end
      @backend.update(c.to_h)
      refresh(c)
    end
  end

  # The undo record is a plain hash, not the Contact object, for the same
  # memory-safety reason described at the top of this class: a removed contact
  # must never be handed back out or re-inserted.
  def delete_contact(contact)
    find_position(contact).then do |position|
      if position
        contact.to_h.then do |data|
          @backend.delete(contact.id)
          @ordered.delete_at(position)
          @list_store.remove(position)
          { position: position, data: data, display_name: data_display_name(data) }
        end
      end
    end
  end

  # Returns the newly built Contact — not the one that was deleted, which no
  # longer exists.
  def restore_contact(undo_info)
    Contact.from_h(undo_info[:data]).tap do |contact|
      @backend.create(contact.to_h)
      [undo_info[:position], @ordered.length].min.then do |position|
        @ordered.insert(position, contact)
        @list_store.insert(position, contact)
      end
      resort
    end
  end

  # Imports a batch of contact hashes, skipping any whose id already exists.
  # Returns the contacts that were actually added.
  def import(hashes)
    hashes.reject { |hash| known_id?(hash[:id] || hash['id']) }
          .map { |hash| add_contact(**Contact.from_h(hash).to_h) }
  end

  def toggle_favorite(contact) = set_favorite(contact, !contact.favorite?)

  def set_favorite(contact, value)
    contact.tap do |c|
      c.favorite = value
      @backend.update(c.to_h)
      refresh(c)
    end
  end

  # --- Link suggestions ---------------------------------------------------

  # Contacts that look like the same person as the given one: upstream
  # suggests linking when an email address, a phone number or the display name
  # matches. Returns them most-similar first.
  def link_suggestions_for(contact)
    @ordered.reject { |other| other.id == contact.id }
            .map { |other| [other, similarity(contact, other)] }
            .select { |_, score| score.positive? }
            .sort_by { |_, score| -score }
            .map(&:first)
  end

  # An exact email match is the strongest signal, then a phone number, then an
  # identical display name.
  def similarity(one, other)
    score = 0
    if shares_any?(one.emails, other.emails) { |v| v.value.downcase }
      score += 3
    end
    if shares_any?(one.phones, other.phones) { |v| v.value.gsub(/[^0-9]/, '') }
      score += 2
    end
    if one.display_name.casecmp(other.display_name).zero?
      score += 1
    end
    score
  end

  def shares_any?(mine, theirs, &normalize)
    values_of(mine, &normalize).intersect?(values_of(theirs, &normalize))
  end

  def values_of(values, &normalize)
    values.reject(&:empty?).map(&normalize).reject(&:empty?).to_set
  end

  private

    def valid_index(index)
      if index.nil? || index == INVALID_POSITION || index.negative?
        nil
      else
        index
      end
    end

  # Coerces plain hashes coming from the editor or a backend into the
  # TypedValue/Role objects Contact stores. Values that are already coerced
  # pass through untouched, so normalising twice is harmless.
    COERCIONS = {
      roles:           ->(value) { Array(value).map { |v| Role.coerce(v) } },
      im_addresses:    ->(value) { Array(value).map { |v| ImAddress.coerce(v) } },
      structured_name: ->(value) { StructuredName.coerce(value) },
      avatar:          ->(value) { Avatar.coerce(value) },
      birthday:        ->(value) { Contact.parse_birthday(value) },
    }.freeze

    def normalize(attributes)
      attributes.dup.tap do |result|
        MULTI_VALUE_FIELDS.each do |field|
          if result.key?(field)
            result[field] = Array(result[field]).map { |v| TypedValue.coerce(v) }
          end
        end

        COERCIONS.each do |field, coerce|
          if result.key?(field)
            result[field] = coerce.call(result[field])
          end
        end
      end
    end

  # Gio::ListStore has no "this item changed" signal, so re-emitting
  # items-changed for the contact's row is what makes the list view rebind it.
    def refresh(contact)
      find_position(contact).then do |position|
        if position
          @list_store.items_changed(position, 1, 1)
        end
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
        @ordered.sort_by { |contact| sort_key(contact) }.then do |sorted|
          unless sorted == @ordered
            @ordered = sorted
            @list_store.splice(0, @list_store.n_items, sorted)
          end
        end
        restore_selection(previously_selected)
      end
    end

    def sort_key(contact)
      [contact.favorite? ? 0 : 1,
       contact.sort_name(on_surname: @sort_on_surname).downcase,
       contact.id.to_s
  ]
    end

  # Splicing resets the selection model, so put the cursor back where it was.
    def restore_selection(contact)
      contact.then do |target|
        position_in_view(target).then do |index|
          if target && index
            selection_model.selected = index
          end
        end
      end
    end

    def position_in_view(contact)
      contact.then do |target|
        if target
          visible_contacts.index { |other| other.id == target.id }
        end
      end
    end

    def find_position(contact) = @ordered.index { |other| other.id == contact.id }

    def known_id?(id) = !id.nil? && @ordered.any? { |contact| contact.id == id }

    def matches_query?(item, query)
      searchable_fields(item).any? { |field| field.to_s.downcase.include?(query) }
    end

    def searchable_fields(item)
      [
        item.name,
        item.alias_name,
        item.nickname,
        item.structured_name.to_s,
        item.im_addresses.map(&:value),
        item.emails.map(&:value),
        item.phones.map(&:value),
        item.addresses.map(&:value),
        item.roles.map { |r| [r.organization, r.title] },
        item.notes.map(&:value),
      ].flatten
    end

  # A name for an undo record, taken from the serialised data so it never
  # touches the deleted object.
    def data_display_name(data)
      [data[:alias], data[:name], data[:nickname]].map(&:to_s)
                                                  .find { |v| !v.strip.empty? }
                                                  .then do |named|
        if named
          named
        else
          Contact.from_h(data).display_name
        end
      end
    end
end
