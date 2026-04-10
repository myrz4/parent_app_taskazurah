importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBiuQTwMUfk-rpgp3I6GZ2-AZ6viNjaZq0',
  appId: '1:50258061076:web:b579cbc8f03236be648401',
  messagingSenderId: '50258061076',
  projectId: 'taskazurah',
  authDomain: 'taskazurah.firebaseapp.com',
  storageBucket: 'taskazurah.firebasestorage.app',
  measurementId: 'G-YRMKREZXRY',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload && payload.notification ? payload.notification : {};
  const title = notification.title || 'Taska Zurah';
  const options = {
    body: notification.body || 'You have a new billing or attendance update.',
    icon: '/icons/Icon-192.png',
  };

  self.registration.showNotification(title, options);
});