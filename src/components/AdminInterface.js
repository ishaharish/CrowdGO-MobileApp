import React, { useState } from 'react';
import { collection, addDoc, doc, getDoc, updateDoc } from 'firebase/firestore';
import { db } from '../firebase-config'; // adjust path as needed
import QRCodeScanner from './QRCodeScanner';

function AdminInterface() {
  const [eventForm, setEventForm] = useState({
    name: '',
    date: '',
    description: '',
    location: '',
    createdAt: new Date(),
    updatedAt: new Date()
  });

  const handleQRScan = async (scannedData) => {
    if (scannedData) {
      try {
        // If the scanned data contains an event ID, fetch the event from Firebase
        if (scannedData.id) {
          const eventDoc = doc(db, 'events', scannedData.id);
          const eventSnapshot = await getDoc(eventDoc);
          
          if (eventSnapshot.exists()) {
            const eventData = eventSnapshot.data();
            setEventForm({
              ...eventData,
              id: eventSnapshot.id,
              date: eventData.date // Assuming date is stored as string in Firebase
            });
          }
        } else {
          // Handle scanned data that doesn't come from our system
          setEventForm({
            name: scannedData.name || '',
            date: scannedData.date || '',
            description: scannedData.description || '',
            location: scannedData.location || '',
            createdAt: new Date(),
            updatedAt: new Date()
          });
        }
      } catch (error) {
        console.error('Error processing QR code:', error);
        alert('Error processing QR code');
      }
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const eventData = {
        ...eventForm,
        updatedAt: new Date()
      };

      if (eventForm.id) {
        // Update existing event
        const eventDoc = doc(db, 'events', eventForm.id);
        await updateDoc(eventDoc, eventData);
        alert('Event updated successfully!');
      } else {
        // Create new event
        const eventsCollection = collection(db, 'events');
        await addDoc(eventsCollection, eventData);
        alert('Event created successfully!');
      }

      // Reset form
      setEventForm({
        name: '',
        date: '',
        description: '',
        location: '',
        createdAt: new Date(),
        updatedAt: new Date()
      });
    } catch (error) {
      console.error('Error saving event:', error);
      alert('Failed to save event');
    }
  };

  return (
    <div className="admin-interface">
      <div className="admin-container">
        <div className="form-section">
          <h2>{eventForm.id ? 'Edit Event' : 'Create Event'}</h2>
          <form className="event-form" onSubmit={handleSubmit}>
            <div className="form-group">
              <label htmlFor="name">Event Name:</label>
              <input
                id="name"
                type="text"
                value={eventForm.name}
                onChange={(e) => setEventForm(prev => ({ ...prev, name: e.target.value }))}
                placeholder="Event Name"
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="date">Date:</label>
              <input
                id="date"
                type="date"
                value={eventForm.date}
                onChange={(e) => setEventForm(prev => ({ ...prev, date: e.target.value }))}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="description">Description:</label>
              <textarea
                id="description"
                value={eventForm.description}
                onChange={(e) => setEventForm(prev => ({ ...prev, description: e.target.value }))}
                placeholder="Event Description"
              />
            </div>

            <div className="form-group">
              <label htmlFor="location">Location:</label>
              <input
                id="location"
                type="text"
                value={eventForm.location}
                onChange={(e) => setEventForm(prev => ({ ...prev, location: e.target.value }))}
                placeholder="Event Location"
              />
            </div>

            <button type="submit" className="submit-button">
              {eventForm.id ? 'Update Event' : 'Create Event'}
            </button>
          </form>
        </div>

        <div className="scanner-section">
          <h2>Scan Event QR Code</h2>
          <QRCodeScanner onScanSuccess={handleQRScan} />
        </div>
      </div>
    </div>
  );
}

export default AdminInterface; 