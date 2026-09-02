# frozen_string_literal: true

require_relative 'test_helper'
require 'shell_search_provider'

class TestShellSearchProvider < Minitest::Test
  include TempData

  def store
    @store ||= ContactStore.new(backend: Backends::JsonBackend.new(path: json_path)).tap do |s|
      s.add_contact(id: 'ada', name: 'Ada Lovelace',
                    emails: [{ value: 'ada@analytical.engine', type: 'Work' }],
                    roles: [{ organization: 'Analytical Engine Co', title: 'Mathematician', type: 'Work' }])
      s.add_contact(id: 'grace', name: 'Grace Hopper',
                    phones: [{ value: '+1 555 0100', type: 'Mobile' }])
    end
  end

  def provider = @provider ||= ShellSearchProvider.new(store)

  # The shell splits the typed query on whitespace and passes the terms
  # separately, so every term has to match for the contact to be returned.
  def test_every_term_must_match
    assert_equal ['ada'], provider.initial_result_set(%w[ada lovelace])
    assert_empty provider.initial_result_set(%w[ada hopper])
  end

  def test_search_covers_the_same_fields_as_the_in_app_search
    assert_equal ['ada'], provider.initial_result_set(['analytical'])
    assert_equal ['ada'], provider.initial_result_set(['mathematician'])
    assert_equal ['grace'], provider.initial_result_set(['555'])
  end

  def test_search_is_case_insensitive
    assert_equal ['ada'], provider.initial_result_set(['LOVELACE'])
  end

  def test_empty_terms_return_nothing
    assert_empty provider.initial_result_set([])
    assert_empty provider.initial_result_set([''])
  end

  def test_subsearch_narrows_the_previous_results
    provider.initial_result_set(['a']).then do |first_pass|
      assert_equal 2, first_pass.length
      assert_equal ['grace'], provider.subsearch_result_set(first_pass, ['hopper'])
    end
  end

  def test_subsearch_cannot_widen_beyond_the_previous_results
    assert_empty provider.subsearch_result_set(['grace'], ['lovelace'])
  end

  def test_result_metas_describe_each_contact
    provider.result_metas(%w[ada grace]).then do |metas|
      assert_equal %w[ada grace], metas.map { |m| m['id'] }
      assert_equal 'Ada Lovelace', metas.first['name']
      assert_equal 'Mathematician at Analytical Engine Co', metas.first['description']
      assert_equal '+1 555 0100', metas.last['description']
    end
  end

  def test_result_metas_skips_unknown_ids
    assert_empty provider.result_metas(['nope'])
  end

  def test_activate_and_launch_call_back
    activated = nil
    launched = nil
    ShellSearchProvider.new(store, on_activate: ->(id) { activated = id },
                                   on_launch: ->(q) { launched = q }).then do |p|
      p.activate_result('ada', [], 0)
      p.launch_search(%w[ada lovelace], 0)
      assert_equal 'ada', activated
      assert_equal 'ada lovelace', launched
    end
  end

  # The interface has to parse, or the shell could never call us.
  def test_the_dbus_interface_is_well_formed
    provider.interface_info.then do |info|
      assert_equal ShellSearchProvider::INTERFACE, info.name
    end
  end

  # GLib::Variant.new cannot build a{sv} or a reply tuple in these bindings,
  # so the reply variants are parsed from GVariant text — which means the
  # text has to be escaped correctly.
  def test_reply_variants_have_the_types_dbus_expects
    provider.send(:string_array, %w[ada grace]).then do |variant|
      assert_equal '(as)', variant.type.to_s
      assert_equal [%w[ada grace]], variant.value
    end

    provider.send(:metas_variant, provider.result_metas(['ada'])).then do |variant|
      assert_equal '(aa{sv})', variant.type.to_s
    end
  end

  def test_quotes_and_backslashes_in_a_name_do_not_break_the_variant
    store.add_contact(id: 'quoted', name: 'Ada "The\\Enchantress" Lovelace')
    provider.result_metas(['quoted']).then do |metas|
      assert_equal '(aa{sv})', provider.send(:metas_variant, metas).type.to_s
    end
  end

  def test_results_are_capped
    (ShellSearchProvider::MAX_RESULTS + 5).times { |i| store.add_contact(name: "Person #{i}") }
    assert_equal ShellSearchProvider::MAX_RESULTS, provider.initial_result_set(['person']).length
  end
end
