# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationErrorDetail, type: :model do
  it { is_expected.to belong_to(:integration) }
  it { is_expected.to belong_to(:owner) }
end
