class AddAnniversaryDateToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :anniversary_date, :date
  end
end
