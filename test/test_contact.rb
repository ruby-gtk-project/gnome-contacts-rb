# frozen_string_literal: true

require_relative 'test_helper'
require 'contact'

class TestTypedValue < Minitest::Test
  def test_coerce_passes_typed_values_through_unchanged
    TypedValue.new(value: 'a@b.com', type: 'Work').then do |original|
      assert_same original, TypedValue.coerce(original)
    end
  end

  # Regression: normalising twice used to produce a TypedValue whose value was
  # the inspect string of another TypedValue.
  def test_coerce_is_idempotent
    TypedValue.coerce(TypedValue.coerce({ value: 'a@b.com', type: 'Work' })).then do |coerced|
      assert_equal 'a@b.com', coerced.value
      assert_equal 'Work', coerced.type
    end
  end

  def test_coerce_accepts_string_and_string_keyed_hash
    assert_equal 'x@y.z', TypedValue.coerce('x@y.z').value
    assert_equal 'Work', TypedValue.coerce({ 'value' => 'x@y.z', 'type' => 'work' }).type
  end

  def test_empty_ignores_whitespace
    assert_predicate TypedValue.new(value: '   ', type: 'Work'), :empty?
    refute_predicate TypedValue.new(value: 'a', type: 'Work'), :empty?
  end
end

class TestRole < Minitest::Test
  def test_coerce_is_idempotent
    Role.coerce(Role.coerce({ organization: 'Acme', title: 'Engineer', type: 'Work' })).then do |role|
      assert_equal 'Acme', role.organization
      assert_equal 'Engineer', role.title
    end
  end

  def test_display_joins_title_and_organization
    assert_equal 'Engineer at Acme', Role.new(organization: 'Acme', title: 'Engineer', type: 'Work').display
    assert_equal 'Acme', Role.new(organization: 'Acme', title: '', type: 'Work').display
    assert_equal 'Engineer', Role.new(organization: '', title: 'Engineer', type: 'Work').display
  end
end

class TestContact < Minitest::Test
  include TempData

  def test_display_name_falls_back_through_email_and_phone
    assert_equal 'Ada', build(name: 'Ada').display_name
    assert_equal 'a@b.com', build(emails: [{ value: 'a@b.com', type: 'Work' }]).display_name
    assert_equal '555', build(phones: [{ value: '555', type: 'Home' }]).display_name
    assert_equal 'Unnamed Contact', build.display_name
  end

  def test_initials_uses_the_first_and_last_name
    assert_equal 'AL', build(name: 'Ada Lovelace').initials
    assert_equal 'AL', build(name: 'Ada Byron King Lovelace').initials
    assert_equal 'A', build(name: 'Ada').initials
  end

  def test_from_h_round_trips_through_to_h
    Contact.from_h(full_contact_attributes.merge(id: 'abc')).then do |contact|
      Contact.from_h(contact.to_h).then do |round_tripped|
        assert_equal contact.name, round_tripped.name
        assert_equal contact.emails, round_tripped.emails
        assert_equal contact.roles, round_tripped.roles
        assert_equal contact.birthday, round_tripped.birthday
        assert_equal contact.favorite?, round_tripped.favorite?
      end
    end
  end

  def test_from_h_reads_the_legacy_single_value_format
    Contact.from_h(id: '1', name: 'Ada', email: 'a@b.com', phone: '555',
                   organization: 'Acme', title: 'Engineer').then do |contact|
      assert_equal ['a@b.com'], contact.emails.map(&:value)
      assert_equal ['555'], contact.phones.map(&:value)
      assert_equal 'Engineer at Acme', contact.role_display
    end
  end

  def test_to_h_drops_empty_values
    build(emails: [{ value: '', type: 'Work' }, { value: 'a@b.com', type: 'Work' }]).then do |contact|
      assert_equal 1, contact.to_h[:emails].length
    end
  end

  def test_birthday_parses_iso_strings_and_survives_garbage
    assert_equal Date.new(1815, 12, 10), Contact.parse_birthday('1815-12-10')
    assert_equal 'not a date', Contact.parse_birthday('not a date')
    assert_nil Contact.parse_birthday(nil)
  end

  def test_birthday_today
    refute_predicate build(birthday: '1815-12-10'), :birthday_today?
    assert_predicate build(birthday: Date.today.strftime('1900-%m-%d')), :birthday_today?
  end

  private

  def build(**attrs) = Contact.from_h({ id: 'test' }.merge(attrs))
end
