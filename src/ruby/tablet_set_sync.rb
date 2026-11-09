# Which tablet sets in the database are no longer configured (in
# /data/tablets/tablet_sets.yaml) and get removed at startup – together with
# all their bookings. If the configuration lists no tablet sets at all (file
# missing, unreadable or empty, e.g. a broken mount), nothing is removed:
# that is far more likely an accident than a school without tablet sets.
module TabletSetSync
    def self.ids_to_remove(existing_ids, configured_ids)
        configured = configured_ids.to_a
        return [] if configured.empty?
        existing_ids.to_a - configured
    end
end
