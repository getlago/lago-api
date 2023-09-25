# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::DeleteEventsJob, type: :job, transaction: false do
  let(:billable_metric) { create(:billable_metric, :deleted) }
  let(:subscription) { create(:subscription) }

  it 'deletes related events' do
    create(:standard_charge, plan: subscription.plan, billable_metric:)
    event = create(:event, code: billable_metric.code, subscription:)
    quantified_event = create(:quantified_event, billable_metric:)

    freeze_time do
      expect { described_class.perform_now(billable_metric) }
        .to change { event.reload.deleted_at }.from(nil).to(Time.current)
        .and change { quantified_event.reload.deleted_at }.from(nil).to(Time.current)
    end
  end
end
