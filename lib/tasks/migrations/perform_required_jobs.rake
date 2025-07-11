# frozen_string_literal: true

# This task is used to perform the required jobs for the migrations.
# And is to be changed depending on what is required for the next version.
namespace :migrations do
  desc "Perform the required jobs for the migrations"
  task perform_required_jobs: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    resources_to_fill = [
      {model: Payment, job: DatabaseMigrations::PopulatePaymentsWithCustomerId}
    ]

    puts "##################################\nStarting required jobs"
    puts "\n#### Checking for resource to fill ####"

    to_fill = []

    resources_to_fill.each do |resource|
      model = resource[:model]
      pp "- Checking #{model.name}: 🔎"
      count = model.where(customer_id: nil).count

      if count > 0
        to_fill << resource
        pp "  -> #{count} records to fill 🧮"
      else
        pp "  -> Nothing to do ✅"
      end
    end

    if to_fill.any?
      puts "\n#### Enqueue jobs in the low_priority queue ####"
      to_fill.each do |resource|
        pp "- Enqueuing #{resource[:job].name}"
        resource[:job].perform_later
      end
    end

    while to_fill.present?
      sleep 5
      puts "\n#### Checking status ####"

      to_delete = []
      to_fill.each do |resource|
        model = resource[:model]
        pp "- Checking #{model.name}: 🔎"
        count = model.where(customer_id: nil).count

        if count > 0
          pp "  -> #{count} remaining 🧮"
        else
          to_delete << resource
          pp "  -> Done ✅"
        end
      end

      to_delete.each { to_fill.delete(it) }
    end

    puts "\n#### All good, ready to Upgrade! ✅ ####"
  end
end