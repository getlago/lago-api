# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupProperty, type: :model do
  describe '#kept?' do
    it 'returns if group property is kept' do
      group_property = create(:group_property)
      expect(group_property).to be_kept

      group_property.group.discard!
      expect(group_property).not_to be_kept

      group_property.group.undiscard!
      group_property.discard!
      expect(group_property).not_to be_kept
    end
  end
end
