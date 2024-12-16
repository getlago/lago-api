# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InboundWebhook, type: :model do
  subject(:inbound_webhook) { build(:inbound_webhook) }

  it { is_expected.to belong_to(:organization) }

  it { is_expected.to validate_presence_of(:event_type) }
  it { is_expected.to validate_presence_of(:payload) }
  it { is_expected.to validate_presence_of(:source) }
  it { is_expected.to validate_presence_of(:status) }

  it { is_expected.to be_pending }
end
