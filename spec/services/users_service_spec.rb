# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsersService, type: :service do
  subject { described_class.new }

  describe 'new_token' do
    let(:user) { create(:user) }

    it 'generates a jwt token for the user' do
      result = subject.new_token(user)

      expect(result).to be_success
      expect(result.user).to eq(user)
      expect(result.token).to be_present
    end
  end
end
