import { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

function App() {
  const [message, setMessage] = useState('Загрузка...');

  useEffect(() => {
    // ВАЖНО: на Шаге 9 замени IP_СЕРВЕРА на реальный IP твоего VPS
    axios.get('http://IP_СЕРВЕРА:8000/api/hello/')
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
