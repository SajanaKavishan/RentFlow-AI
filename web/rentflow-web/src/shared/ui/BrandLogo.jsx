import mark from '../../assets/rentflow-mark.png'
import wordmark from '../../assets/rentflow-wordmark.png'

export function BrandMark({ className = '', decorative = false }) {
  return <img className={className} src={mark} alt={decorative ? '' : 'RentFlow AI'} />
}

export function BrandWordmark({ className = '', decorative = false }) {
  return <img className={className} src={wordmark} alt={decorative ? '' : 'RentFlow AI'} />
}
