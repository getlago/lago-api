# frozen_string_literal: true

class AddSlugToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :slug, :string
<<<<<<< HEAD
    add_column :customers, :sequential_id, :bigint

    LagoApi::Application.load_tasks
    Rake::Task['customers:generate_slug'].invoke
=======
>>>>>>> 52d78a6... add files
  end
end
