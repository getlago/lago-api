# frozen_string_literal: true

require "rails_helper"

RSpec.describe Permission do
  it "defines permission hashes" do
    names = %w[DEFAULT_PERMISSIONS_HASH ADMIN_PERMISSIONS_HASH MANAGER_PERMISSIONS_HASH FINANCE_PERMISSIONS_HASH]

    names.each do |name|
      expect(described_class).to be_const_defined(name)

      hash = described_class.const_get(name)
      expect(hash).to be_a(Hash) # transform_values returns a Hash, not a DottedHash
      expect(hash).to be_frozen
      expect(hash.values).to all(be_in([true, false]))
      expect(hash.keys).to all(be_a(String))
    end

    %w[ADMIN_PERMISSIONS_HASH MANAGER_PERMISSIONS_HASH FINANCE_PERMISSIONS_HASH].each do |name|
      expect(described_class::DEFAULT_PERMISSIONS_HASH.keys).to match_array(described_class.const_get(name).keys)
    end
  end
end
