// WebSocket Service - Handles real-time communication
class WebSocketService {
  constructor(config) {
    this.config = config;
    this.ws = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 1000;
    this.isConnected = false;
    this.listeners = new Map();
    this.pendingMessages = [];
  }

  // Connect to WebSocket (ActionCable)
  connect() {
    try {
      // Use ActionCable for WebSocket connection
      if (window.App && window.App.cable) {
        this.cable = window.App.cable;
      } else {
        // Fallback to regular WebSocket if ActionCable not available
        const wsUrl = `wss://${window.location.host}/cable`;
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = this.handleOpen.bind(this);
        this.ws.onmessage = this.handleMessage.bind(this);
        this.ws.onclose = this.handleClose.bind(this);
        this.ws.onerror = this.handleError.bind(this);
      }
      
      console.log('WebSocket connecting to jukebox:', this.config.sessionId);
    } catch (error) {
      console.error('Failed to create WebSocket:', error);
      this.attemptReconnect();
    }
  }

  // Handle WebSocket open
  handleOpen(event) {
    console.log('WebSocket connected');
    this.isConnected = true;
    this.reconnectAttempts = 0;
    
    // Send any pending messages
    this.pendingMessages.forEach(message => {
      this.send(message);
    });
    this.pendingMessages = [];
    
    this.notifyListeners('connected', { event });
  }

  // Handle WebSocket message
  handleMessage(event) {
    try {
      const data = JSON.parse(event.data);
      console.log('WebSocket message received:', data);
      
      // Notify listeners based on message type
      if (data.type) {
        this.notifyListeners(data.type, data.data);
      }
      
      // Generic message listener
      this.notifyListeners('message', data);
    } catch (error) {
      console.error('Failed to parse WebSocket message:', error);
    }
  }

  // Handle WebSocket close
  handleClose(event) {
    console.log('WebSocket disconnected:', event.code, event.reason);
    this.isConnected = false;
    this.notifyListeners('disconnected', { event });
    
    if (!event.wasClean) {
      this.attemptReconnect();
    }
  }

  // Handle WebSocket error
  handleError(error) {
    console.error('WebSocket error:', error);
    this.notifyListeners('error', { error });
  }

  // Attempt to reconnect
  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.log('Max reconnection attempts reached');
      this.notifyListeners('reconnect_failed', { attempts: this.reconnectAttempts });
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * this.reconnectAttempts;
    
    console.log(`Attempting to reconnect in ${delay}ms (attempt ${this.reconnectAttempts})`);
    
    setTimeout(() => {
      this.connect();
    }, delay);
  }

  // Send message
  send(message) {
    if (this.isConnected && this.ws) {
      try {
        this.ws.send(JSON.stringify(message));
        return true;
      } catch (error) {
        console.error('Failed to send WebSocket message:', error);
        return false;
      }
    } else {
      // Queue message for when connection is restored
      this.pendingMessages.push(message);
      return false;
    }
  }

  // Send playback status
  sendPlaybackStatus(status) {
    return this.send({
      type: 'playback_status',
      data: {
        sessionId: this.config.sessionId,
        timestamp: new Date().toISOString(),
        ...status
      }
    });
  }

  // Send song request
  sendSongRequest(songId, requestedBy) {
    return this.send({
      type: 'song_request',
      data: {
        sessionId: this.config.sessionId,
        songId: songId,
        requestedBy: requestedBy,
        timestamp: new Date().toISOString()
      }
    });
  }

  // Send queue update
  sendQueueUpdate(queue) {
    return this.send({
      type: 'queue_update',
      data: {
        sessionId: this.config.sessionId,
        queue: queue,
        timestamp: new Date().toISOString()
      }
    });
  }

  // Add event listener
  addEventListener(eventType, callback) {
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, []);
    }
    this.listeners.get(eventType).push(callback);
  }

  // Remove event listener
  removeEventListener(eventType, callback) {
    if (this.listeners.has(eventType)) {
      const callbacks = this.listeners.get(eventType);
      const index = callbacks.indexOf(callback);
      if (index > -1) {
        callbacks.splice(index, 1);
      }
    }
  }

  // Notify listeners
  notifyListeners(eventType, data) {
    if (this.listeners.has(eventType)) {
      this.listeners.get(eventType).forEach(callback => {
        try {
          callback(data);
        } catch (error) {
          console.error('Error in WebSocket listener:', error);
        }
      });
    }
  }

  // Get connection status
  getStatus() {
    return {
      isConnected: this.isConnected,
      reconnectAttempts: this.reconnectAttempts,
      pendingMessages: this.pendingMessages.length
    };
  }

  // Disconnect
  disconnect() {
    if (this.ws) {
      this.ws.close(1000, 'Client disconnecting');
      this.ws = null;
    }
    this.isConnected = false;
    this.pendingMessages = [];
  }
}
