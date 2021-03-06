# s2.2.7.8

EventEmitter = require('events').EventEmitter

types =
  1:
    name: 'DATABASE'
    event: 'databaseChange'
  2:
    name: 'LANGUAGE',
    event: 'languageChange'
  3:
    name: 'CHARSET'
    event: 'charsetChange'
  4:
    name: 'PACKET_SIZE'
    event: 'packetSizeChange'
  7:
    name: 'SQL_COLLATION'
    event: 'sqlCollationChange'
  8:
    name: 'BEGIN_TXN'
  9:
    name: 'COMMIT_TXN'
  10:
    name: 'ROLLBACK_TXN'
  13:
    name: 'REALTIME_LOG_SHIPPING'
    event: 'mirrorStateChange'
  17:
    name: 'TXN_ENDED'

module.exports = (buffer) ->
  length = buffer.readUInt16LE()
  typeNumber = buffer.readUInt8()
  type = types[typeNumber]

  if type
    switch type.name
      when 'DATABASE', 'LANGUAGE', 'CHARSET', 'PACKET_SIZE'
        newValue = buffer.readBVarchar()
        oldValue = buffer.readBVarchar()
      when 'SQL_COLLATION'
        valueLength = buffer.readUInt8()
        newValue = buffer.readBuffer(valueLength)

        valueLength = buffer.readUInt8()
        oldValue = buffer.readBuffer(valueLength)
      when 'REALTIME_LOG_SHIPPING'
        newValue = buffer.readBVarchar()
        oldValue = buffer.readBVarchar()
      else
        throw new Error("Unsupported ENVCHANGE type #{typeNumber} #{type.name} at offset #{buffer.position - 1}")

    if type.name == 'PACKET_SIZE'
      newValue = parseInt(newValue)
      oldValue = parseInt(oldValue)
  else
    throw new Error("Unsupported ENVCHANGE type #{typeNumber} at offset #{buffer.position - 1}")

  # Return token
  name: 'ENVCHANGE'
  type: type.name
  event: type.event
  oldValue: oldValue
  newValue: newValue
