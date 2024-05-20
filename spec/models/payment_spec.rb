# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payment, type: :model do
  subject(:payment) { create(:payment) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:integration_resources) }
  it { is_expected.to delegate_method(:customer).to(:invoice) }
end
