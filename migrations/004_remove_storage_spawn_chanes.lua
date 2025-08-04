-- Removes spawn changes entirely from storage (persisted)
if storage.spawn_chances then
  storage.ruin_queue = nil
end
