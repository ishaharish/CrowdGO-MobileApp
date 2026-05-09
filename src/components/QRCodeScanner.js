import React, { useState } from 'react';
import { QrReader } from 'react-qr-reader';

const QRCodeScanner = ({ onScanSuccess }) => {
  const [error, setError] = useState(null);

  const handleScan = (result) => {
    if (result) {
      try {
        const eventData = JSON.parse(result?.text);
        onScanSuccess(eventData);
      } catch (err) {
        setError('Invalid QR code format');
      }
    }
  };

  const handleError = (err) => {
    setError('Error accessing camera: ' + err.message);
  };

  return (
    <div className="qr-scanner-container">
      <h3>Scan Event QR Code</h3>
      {error && <p className="error-message">{error}</p>}
      <div style={{ width: '300px', margin: '0 auto' }}>
        <QrReader
          constraints={{ facingMode: 'environment' }}
          onResult={handleScan}
          onError={handleError}
          style={{ width: '100%' }}
        />
      </div>
      <p className="scanner-help-text">Point your camera at an event QR code</p>
    </div>
  );
};

export default QRCodeScanner; 