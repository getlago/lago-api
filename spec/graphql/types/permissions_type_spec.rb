# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::PermissionsType do
  it 'matches the dumped schema' do
    all_boolean = described_class.fields.values.all? do |f|
      f.type.to_type_signature == 'Boolean!'
    end
    expect(all_boolean).to be_truthy

    field_names = described_class.fields.keys.map(&:underscore)
    expect(field_names).to match_array(Permission::DEFAULT_PERMISSIONS_HASH.keys)
  end
end
