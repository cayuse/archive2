# Rows that are unique by a natural key get an id derived from that key when they are created, so
# two peers that create "the same" row independently (both import the same album before they have
# heard from each other) create the same id. Replication then settles the clash on that one row.
# Without this, pglogical settles a clash on a unique key by replacing one peer's row with the
# other's, id and all, and whatever pointed at the replaced id points at nothing (see PeerSync).
#
#   natural_id { musicbrainz_id }   # nil = no natural key for this row: a random id as usual
module NaturalId
  extend ActiveSupport::Concern
  NAMESPACE = "6d1f6c2e-3c8b-4b52-9a51-2d8f0c7d4a10".freeze   # fixed for ever: changing it changes every derived id

  class_methods do
    def natural_id(&key)
      before_create do
        value = instance_exec(&key)
        self.id ||= NaturalId.for(self.class, value) if value.present?
      end
    end
  end

  def self.for(klass, value)
    Digest::UUID.uuid_v5(NAMESPACE, "#{klass.table_name}:#{value}")
  end
end
