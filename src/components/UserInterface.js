import React, { useState, useEffect } from 'react';
import { collection, getDocs } from 'firebase/firestore';
import { db } from '../firebase-config'; // adjust path as needed
import QRCodeDisplay from './QRCodeDisplay';

function UserInterface() {
  const [selectedEvent, setSelectedEvent] = useState(null);
  const [events, setEvents] = useState([]);
  
  useEffect(() => {
    const fetchEvents = async () => {
      try {
        const eventsCollection = collection(db, 'events');
        const eventsSnapshot = await getDocs(eventsCollection);
        const eventsList = eventsSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }));
        setEvents(eventsList);
        console.log('Fetched events:', eventsList); // Debug log
      } catch (error) {
        console.error('Error fetching events:', error);
      }
    };

    fetchEvents();
  }, []);

  const handleEventSelect = (e) => {
    const event = events.find(evt => evt.id === e.target.value);
    setSelectedEvent(event);
    console.log('Selected event:', event); // Debug log
  };

  return (
    <div className="user-interface">
      <div className="event-selection-section">
        <h2>Select an Event</h2>
        <select 
          onChange={handleEventSelect}
          className="event-select"
          value={selectedEvent?.id || ''}
        >
          <option value="">Select an event</option>
          {events.map(event => (
            <option key={event.id} value={event.id}>
              {event.name}
            </option>
          ))}
        </select>
      </div>

      {selectedEvent && (
        <div className="event-details">
          <h2>Event Details</h2>
          <div className="event-info">
            <p><strong>Name:</strong> {selectedEvent.name}</p>
            <p><strong>Date:</strong> {new Date(selectedEvent.date).toLocaleDateString()}</p>
            {selectedEvent.description && (
              <p><strong>Description:</strong> {selectedEvent.description}</p>
            )}
            {selectedEvent.location && (
              <p><strong>Location:</strong> {selectedEvent.location}</p>
            )}
          </div>
          
          <div className="qr-section">
            <QRCodeDisplay eventData={selectedEvent} />
          </div>
        </div>
      )}
    </div>
  );
}

export default UserInterface; 