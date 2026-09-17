# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_usage_monitoring_triggered_alerts view" do # rubocop:disable RSpec/DescribeClass
  def row_for(id)
    ActiveRecord::Base.connection.select_one(
      "SELECT * FROM exports_usage_monitoring_triggered_alerts WHERE lago_id = #{ActiveRecord::Base.connection.quote(id)}"
    )
  end

  describe "alert event kinds" do
    it "exports triggers only" do
      triggered = create(:triggered_alert)
      resolved = create(:triggered_alert, kind: :resolved)
      seeded = create(:triggered_alert, kind: :seeded)

      expect(row_for(triggered.id)).to be_present
      expect(row_for(resolved.id)).to be_nil
      expect(row_for(seeded.id)).to be_nil
    end
  end
end
