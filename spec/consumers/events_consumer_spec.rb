# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventsConsumer do
  subject(:consumer) { karafka.consumer_for('events-raw') }

  let(:bm) { create(:sum_billable_metric) }
  let(:organization) { bm.organization }

  let(:code) { bm.code }

  before do
    karafka.produce({
      'code' => code,
      'organization_id' => organization.id,
      'properties' => {}
    }.to_json)
  end

  it "produces events-enriched messages" do
    consumer.consume

    expect(karafka.produced_messages.last[:topic]).to eq('events_enriched')
  end

  context "when billable metric does not exists" do
    let(:code) { "doesnotexists" }

    it "moves the message to the DLQ" do
      consumer.consume

      expect(karafka.produced_messages.last[:topic]).to eq('unprocessed_events')
    end
  end

  context "when billable metric is linked to pay in advance charge" do
    let(:pay_in_advance_charge) { create(:standard_charge, :pay_in_advance, billable_metric: bm) }

    before { pay_in_advance_charge }

    it "enqueues a Events::PayInAdvanceKafkaJob" do
      expect { consumer.consume }.to have_enqueued_job(Events::PayInAdvanceKafkaJob)
    end
  end
end
