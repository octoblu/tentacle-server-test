Meshblu = require 'meshblu-websocket'
through = require 'through'
debug   = require('debug')('meshblu:tentacle-server')
_ = require 'lodash'

TentacleTransformer = require 'tentacle-protocol-buffer'

class Tentacle
  constructor: (tentacleConn, options={}) ->
    @meshbluUrl = options.meshbluUrl || "meshblu.octoblu.com"
    @meshbluPort = options.meshbluPort || 443

    @tentacleTransformer = new TentacleTransformer()
    @tentacleConn = tentacleConn

  start: =>
    debug 'start called'

    @tentacleConn.on 'error', @onTentacleConnectionError
    @tentacleConn.on 'end', @onTentacleConnectionClosed
    @tentacleConn.pipe through(@onTentacleData)

  listenToMeshbluMessages: =>
    return if @alreadyListening

    @meshbluConn.on 'ready',  @onMeshbluReady
    @meshbluConn.on 'notReady', @onMeshbluNotReady
    @meshbluConn.on 'message', @onMeshbluMessage
    @meshbluConn.on 'config', @onMeshbluConfig
    @meshbluConn.on 'whoami', @onMeshbluConfig

    @alreadyListening = true

  onMeshbluReady: =>
    debug "I'm ready!"
    @meshbluConn.whoami()

  onMeshbluNotReady: =>
    debug "I wasn't ready! Auth failed or meshblu blipped"
    @cleanup()

  onMeshbluMessage: (message) =>
    debug "received message\n#{JSON.stringify(message, null, 2)}"
    return unless message?.payload?

    @messageTentacle _.extend({}, message.payload, topic: 'action')

  onMeshbluConfig: (config) =>
    # return @cleanup(error) if error?
    return unless config?.options?

    debug "got config: \n#{JSON.stringify(config, null, 2)}"

    @messageTentacle topic: 'config', pins: config.options.pins

  onTentacleData: (data) =>
    debug "adding #{data.length} bytes from tentacle"
    @parseTentacleMessage data
    @tentacleTransformer.addData data
    @parseTentacleMessage()

  onTentacleConnectionError: (error) =>
    @cleanup error

  onTentacleConnectionClosed: (data) =>
    debug 'client closed the connection'
    @cleanup()

  parseTentacleMessage: =>
    try
      while (message = @tentacleTransformer.toJSON())
        debug "I got the message\n#{JSON.stringify(message, null, 2)}"

        @messageMeshblu(message) if message.topic == 'action'
        @authenticateWithMeshblu(message.authentication) if message.topic == 'authentication'

    catch error
      debug "I got this error: #{error.message}"
      @cleanup()

  messageMeshblu: (msg) =>
    debug "Sending message to meshblu:\n#{JSON.stringify(msg, null, 2)}"
    return unless @meshbluConn?
    @meshbluConn.message devices: '*', payload: msg

  authenticateWithMeshblu: (credentials) =>
      try
        debug "authenticating with credentials: #{JSON.stringify(credentials)}"
        @meshbluConn = new Meshblu(
          uuid:  credentials.uuid
          token: credentials.token
          hostname: @meshbluUrl
          port: @meshbluPort
        )
        @meshbluConn.connect (error)=>
          return @cleanup() if error?
          @listenToMeshbluMessages()

      catch error
        debug "Authentication failed with error: #{error.message}"
        @cleanup()

  messageTentacle: (msg) =>
    debug "Sending message to the tentacle: #{JSON.stringify(msg, null, 2)}"
    @tentacleConn.write @tentacleTransformer.toProtocolBuffer(msg)

  cleanup: (error) =>
    debug "got an error: #{JSON.stringify(error, null, 2)}" if error?
    @tentacleConn.destroy() if @tentacleConn?
    # @meshbluConn.disconnect() if @meshbluConn?

module.exports = Tentacle
