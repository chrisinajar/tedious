buildBuffer = require('./build-buffer')
require('buffertools')
os= require('os')
sprintf = require('sprintf').sprintf
libraryName = require('./library').name

FLAGS_1 =
  ENDIAN_LITTLE: 0x00,
  ENDIAN_BIG: 0x01,
  
  CHARSET_ASCII: 0x00,
  CHARSET_EBCDIC: 0x02,
  
  FLOAT_IEEE_754: 0x00,
  FLOAT_VAX: 0x04,
  FLOAT_ND5000: 0x08,
  
  BCP_DUMPLOAD_ON: 0x00,
  BCP_DUMPLOAD_OFF: 0x10,
  
  USE_DB_ON: 0x00,
  USE_DB_OFF: 0x20,
  
  INIT_DB_WARN: 0x00,
  INIT_DB_FATAL: 0x40,
  
  SET_LANG_WARN_OFF: 0x00,
  SET_LANG_WARN_ON: 0x80,

FLAGS_2 = 
  INIT_LANG_WARN: 0x00,
  INIT_LANG_FATAL: 0x01,

  ODBC_OFF: 0x00,
  ODBC_ON: 0x02,
  
  F_TRAN_BOUNDARY: 0x04,          # Removed in TDS 7.2
  
  F_CACHE_CONNECT: 0x08,          # Removed in TDS 7.2
  
  USER_NORMAL: 0x00,
  USER_SERVER: 0x10, 
  USER_REMUSER: 0x20, 
  USER_SQLREPL: 0x40, 
  
  INTEGRATED_SECURITY_OFF: 0x00,
  INTEGRATED_SECURITY_ON: 0x80

TYPE_FLAGS =
  SQL_DFLT: 0x00,
  SQL_TSQL: 0x01,
  
  OLEDB_OFF: 0x00,
  OLEDB_ON: 0x02,                 # Introduced in TDS 7.2

  READ_ONLY_INTENT: 0x04          # Introduced in TDS 7.4

FLAGS_3 =
  CHANGE_PASSWORD_NO: 0x00,
  CHANGE_PASSWORD_YES: 0x01,      # Introduced in TDS 7.2
  
  BINARY_XML: 0x02,               # Introduced in TDS 7.2
  
  SPAWN_USER_INSTANCE: 0x04,      # Introduced in TDS 7.2

  UNKNOWN_COLLATION_HANDLING: 0x08  # Introduced in TDS 7.3

TDS_VERSION_7_2 = 0x72090002
TDS_VERSION_7_3_A = 0x730A0003
TDS_VERSION_7_3_B = 0x730B0003
DEFAULT_TDS_VERSION = TDS_VERSION_7_2

DEFAULT_PACKET_SIZE = 4 * 1024

###
  s2.2.6.3
###
class Login7Payload
  constructor: (@loginData) ->
    lengthLength = 4

    fixed = @createFixedData()
    variable = @createVariableData(lengthLength + fixed.length)
    length = buildBuffer('U32L', lengthLength + fixed.length + variable.length)

    @data = new Buffer(length.concat(fixed, variable))

  createFixedData: ->
    @tdsVersion = DEFAULT_TDS_VERSION
    @packetSize = DEFAULT_PACKET_SIZE
    @clientProgVer = 0
    @clientPid = process.pid
    @connectionId = 0
    @clientTimeZone = new Date().getTimezoneOffset()
    @clientLcid = 0x00000409                #Can't figure what form this should take.

    @flags1 =
      FLAGS_1.ENDIAN_LITTLE |
      FLAGS_1.CHARSET_ASCII |
      FLAGS_1.FLOAT_IEEE_754 |
      FLAGS_1.BCD_DUMPLOAD_OFF |
      FLAGS_1.USE_DB_OFF |
      FLAGS_1.INIT_DB_WARN |
      FLAGS_1.SET_LANG_WARN_ON

    @flags2 =
      FLAGS_2.INIT_LANG_WARN |
      FLAGS_2.ODBC_OFF |
      FLAGS_2.USER_NORMAL |
      FLAGS_2.INTEGRATED_SECURITY_OFF

    @flags3 =
      FLAGS_3.CHANGE_PASSWORD_NO |
      FLAGS_3.UNKNOWN_COLLATION_HANDLING

    @typeFlags =
      TYPE_FLAGS.SQL_DFLT |
      TYPE_FLAGS.OLEDB_OFF

    buffer = buildBuffer(
      'U32L', @tdsVersion,
      'U32L', @packetSize,
      'U32L', @clientProgVer,
      'U32L', @clientPid,
      'U32L', @connectionId,
      'U8', @flags1,
      'U8', @flags2,
      'U8', @typeFlags,
      'U8', @flags3,
      '32L', @clientTimeZone,
      'U32L', @clientLcid
    )

  createVariableData: (offset) ->
    variableData =
      offsetsAndLengths: new Buffer(0),
      data: new Buffer(0),
      offset: offset + ((9 * 4) + 6 + (3 * 4) + 4)
    
    @hostname = os.hostname()

    @loginData = @loginData || {}
    @loginData.appName = @loginData.appName || 'Tedious'
    @libraryName = libraryName
    
    # Client ID, should be MAC address or other randomly generated GUID like value.
    @clientId = new Buffer([1, 2, 3, 4, 5, 6])

    @sspi = ''
    @attachDbFile = ''
    @changePassword = ''

    cbSSPILong = buildBuffer('U32L', 0)

    @addVariableData(variableData, @hostname)
    @addVariableData(variableData, @loginData.userName)
    @addVariableData(variableData, @createPasswordBuffer())
    @addVariableData(variableData, @loginData.appName)
    @addVariableData(variableData, @loginData.serverName)
    @addVariableData(variableData, '')                        # Reserved for future use.
    @addVariableData(variableData, @libraryName)
    @addVariableData(variableData, @loginData.language)
    @addVariableData(variableData, @loginData.database)
    @addVariableDataBytes(variableData, @clientId)
    @addVariableData(variableData, @sspi)
    @addVariableData(variableData, @attachDbFile)
    @addVariableData(variableData, @changePassword)           # Introduced in TDS 7.2
    @addVariableDataBytes(variableData, cbSSPILong)           # Introduced in TDS 7.2

    variableData.offsetsAndLengths.concat(variableData.data)

  addVariableData: (variableData, value) ->
    if !(value instanceof Buffer)
      value ||= ''
      value = new Buffer(value, 'ucs2')

    offsetAndLength = buildBuffer(
        'U16L', variableData.offset,
        'U16L', value.length / 2
    )

    variableData.offsetsAndLengths = variableData.offsetsAndLengths.concat(offsetAndLength)
    variableData.data = variableData.data.concat(value)
    variableData.offset += value.length

  addVariableDataBytes: (variableData, bytes) ->
    variableData.offsetsAndLengths = variableData.offsetsAndLengths.concat(bytes);

  createPasswordBuffer: () ->
    password = @loginData.password || ''
    password = new Buffer(password, 'ucs2')

    for b in [0..password.length - 1]
      byte = password[b]

      lowNibble = byte & 0x0f
      highNibble = (byte >> 4)
      byte = (lowNibble << 4) | highNibble

      byte = byte ^ 0xa5

      password[b] = byte

    password

  toString: (indent) ->
    indent ||= ''

    indent + 'PreLogin - ' +
      sprintf('TDS:0x%08X, PacketSize:0x%08X, ClientProgVer:0x%08X, ClientPID:0x%08X, ConnectionID:0x%08X',
          @tdsVersion,
          @packetSize,
          @clientProgVer,
          @clientPid,
          @connectionId
      ) + '\n' +
      indent + '           ' +
      sprintf('Flags1:0x%02X, Flags2:0x%02X, TypeFlags:0x%02X, Flags3:0x%02X, ClientTimezone:%d, ClientLCID:0x%08X',
          @flags1,
          @flags2,
          @typeFlags,
          @flags3,
          @clientTimeZone,
          @clientLcid
      ) + '\n' +
      indent + '           ' +
      sprintf("Hostname:'%s', Username:'%s', Password:'%s', AppName:'%s', ServerName:'%s', LibraryName:'%s'",
          @hostname,
          @loginData.userName,
          @loginData.password,
          @loginData.appName,
          @loginData.serverName,
          libraryName
      ) + '\n' +
      indent + '           ' +
      sprintf("Language:'%s', Database:'%s', SSPI:'%s', AttachDbFile:'%s', ChangePassword:'%s'",
          @loginData.language,
          @loginData.database,
          @sspi,
          @attachDbFile
          @changePassword
      )

module.exports = Login7Payload
