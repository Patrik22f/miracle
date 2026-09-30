let bag = 0;
const count = document.querySelector('#bag-count');
count.setAttribute('aria-live', 'polite');
document.querySelectorAll('.add-product').forEach(button => {
  button.addEventListener('click', () => { count.textContent = String(++bag); });
});
