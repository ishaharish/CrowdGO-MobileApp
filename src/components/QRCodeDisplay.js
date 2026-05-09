import React from 'react';
import QRCode from 'qrcode.react';

const QRCodeDisplay = ({ eventData }) => {
  console.log('QRCodeDisplay - Event Data:', eventData); // Debug log

  // Create QR code data with essential event information
  const qrData = JSON.stringify({
    id: eventData.id,
    name: eventData.name,
    date: eventData.date,
    description: eventData.description || '',
    location: eventData.location || ''
  });

  return (
    <div className="qr-code-container">
      <h3 style={{color: '#007bff'}}>Event QR Code</h3>
      <div className="qr-code">
        <QRCode 
          value={qrData}
          size={256}
          level={'H'}
          includeMargin={true}
          renderAs={'canvas'}
        />
      </div>
      <p className="qr-help-text">Scan this code to load event details</p>
      <p style={{color: '#666'}}>QR Code Data: {qrData}</p> {/* Debug info */}
    </div>
  );
};

export default QRCodeDisplay; 