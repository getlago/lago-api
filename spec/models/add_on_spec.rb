# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddOn, type: :model do
  describe 'attached_to_customers?' do
    let(:add_on) { create(:add_on) }

    it { expect(add_on).not_to be_attached_to_customers }

    context 'with attached customers' do
      before { create(:applied_add_on, add_on: add_on) }

      it { expect(add_on).to be_attached_to_customers }
    end
  end

  describe 'deletable?' do
    let(:add_on) { create(:add_on) }

    it { expect(add_on).to be_deletable }

    context 'with attached customers' do
      before { create(:applied_add_on, add_on: add_on) }

      it { expect(add_on).not_to be_deletable }
    end
  end
end
