module MissHannigan
  extend ActiveSupport::Concern

  module ClassMethods
    def has_many(name, scope = nil, **options, &extension)
      nullify_then_purge = detect_nullify_then_purge(options)
      super.tap do |reflection|
        if nullify_then_purge && ActiveRecord::Base.connection.tables.include?(name.to_s)
          connect_nullify_then_purge(reflection, name)
        end
      end
    end

    def has_one(name, scope = nil, **options, &extension)
      nullify_then_purge = detect_nullify_then_purge(options)
      super.tap do |reflection|
        if nullify_then_purge && ActiveRecord::Base.connection.tables.include?(name.to_s)
          connect_nullify_then_purge(reflection, name)
        end
      end
    end

    def detect_nullify_then_purge(options)
      if options[:dependent] == :nullify_then_purge
        options[:dependent] = :nullify
        true
      else
        false
      end
    end

    def connect_nullify_then_purge(reflection, name)
      # has the details of the relation to Child
      reflection_details = reflection[name.to_s]

      # I bet folks are going to forget to do the migration of foreign_keys to accept null. Rails defaults
      # to not allow null.
      if !reflection_details.klass.columns.find { |c| c.name == reflection_details.foreign_key }.null
        raise "The foreign key must be nullable to support MissHannigan. You should create a migration to:
          change_column_null :#{name.to_s}, :#{reflection_details.foreign_key}, true"
      end

      after_destroy do |this_object|
        CleanupJob.perform_later(reflection_details.klass.to_s, reflection_details.foreign_key)
      end
    end
  end

  class CleanupJob < ActiveJob::Base
    queue_as :default

    def perform(klass_string, parent_foreign_key)
      klass = klass_string.constantize

      klass.where(parent_foreign_key => nil).find_each(&:destroy)
    end
  end
end
