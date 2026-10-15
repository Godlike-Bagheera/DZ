import { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

function App() {
  const [message, setMessage] = useState('Загрузка...');

  useEffect(() => {
    // Относительный URL: nginx во фронтенд-контейнере проксирует /api/ на бэкенд.
    // Работает по localhost и по любому IP сервера — ничего менять не нужно.
    axios.get('/api/hello/')
      .then(response => setMessage(response.data.message))
      .catch(error => setMessage('Ошибка: ' + error.message));
  }, []);

  return (
    <div className="App">
      <h1>React фронтенд</h1>
      <p>{message}</p>
    </div>
  );
}

export default App;
