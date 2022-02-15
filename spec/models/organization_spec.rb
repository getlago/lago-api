# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  subject { described_class.new(name: 'PiedPiper') }

  describe 'Validations' do
    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'is not valid without name' do
      subject.name = nil
      expect(subject).to_not be_valid
    end
  end
end
