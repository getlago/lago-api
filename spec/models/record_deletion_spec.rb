# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecordDeletion do
  subject(:record_deletion) { build(:record_deletion) }

  describe "associations" do
    it do
      expect(record_deletion).to belong_to(:organization)
    end
  end
end
