import SvgPath from "svgpath";
import { round, viewBoxHeight, viewBoxWidth } from "./common";

const transformOriginX = 0.5 * viewBoxWidth;
const transformOriginY = 0.45 * viewBoxHeight;

const scaleX = (s: number, x: number) => round((x - transformOriginX) * s + transformOriginX);
const scaleY = (s: number, y: number) => round((y - transformOriginY) * s + transformOriginY);

export const chickenInAnimations = (tokenID: number, s: number) => /*css*/ `
  #ci-chicken-${tokenID} .ci-breath path,
  #ci-chicken-${tokenID} .ci-breath ellipse {
    animation: ci-breath 0.4s infinite ease-in-out alternate;
  }

  #ci-chicken-${tokenID} .ci-wing path {
    animation: ci-wing 3.2s infinite ease-in-out;
    transform-origin: ${scaleX(s, 337.5)}px;
  }

  @keyframes ci-breath {
    0%   { transform: translateY(0);   }
    100% { transform: translateY(${round(s * 5)}px); }
  }

  @keyframes ci-wing {
    0% { transform: translateY(0); }
    5% { transform: translateY(${round(s * 2)}px) rotate(-2deg); }
    12.5% { transform: translateY(${round(s * 5)}px) rotate(1deg); }
    15% { transform: translateY(${round(s * 4)}px) rotate(2deg); }
    25% { transform: translateY(0) rotate(-2deg); }
    35% { transform: translateY(${round(s * 4)}px) rotate(2deg); }
    37.5% { transform: translateY(${round(s * 5)}px) rotate(1deg); }
    40% { transform: translateY(${round(s * 4)}px); }
    50% { transform: translateY(0); }
    62.5% { transform: translateY(${round(s * 5)}px); }
    75% { transform: translateY(0); }
    87.5% { transform: translateY(${round(s * 5)}px); }
    100% { transform: translateY(0); }
  }
`;

const scaleEllipseCoords = (s: number, cx: number, cy: number, rx: number, ry: number) => ({
  cx: scaleX(s, cx),
  cy: scaleY(s, cy),
  rx: round(s * rx),
  ry: round(s * ry),

  toString() {
    return `cx="${this.cx}" cy="${this.cy}" rx="${this.rx}" ry="${this.ry}"`;
  }
});

const scaleRectCoords = (
  s: number,
  x: number,
  y: number,
  width: number,
  height: number,
  rx: number
) => ({
  x: scaleX(s, x),
  y: scaleY(s, y),
  width: round(s * width),
  height: round(s * height),
  rx: round(s * rx),

  toString() {
    return `x="${this.x}" y="${this.y}" width="${this.width}" height="${this.height}" rx="${this.rx}"`;
  }
});

const scalePath = (s: number, p: string) =>
  SvgPath.from(p)
    .translate(-transformOriginX, -transformOriginY)
    .scale(s)
    .translate(transformOriginX, transformOriginY)
    .round(2);

const shadowCoords: [number, number, number, number] = [373, 664, 110, 14];

export const chickenInShadow = (s: number) =>
  /*svg*/ `<ellipse style="mix-blend-mode: soft-light" ${scaleEllipseCoords(s, ...shadowCoords)}/>`;

const legCoords: [number, number, number, number, number][] = [
  [381.15, 597.44, 9.66, 66.38, 4],
  [359.43, 597.44, 9.66, 66.38, 4]
];

const legPaths = [
  "M399.47,659.84l-8.48-9a1.21,1.21,0,0,0-.85-.34h-6.67a16.26,16.26,0,0,0-7.38,2.14l-10.68,6.76c-2.19,1.38-1.06,4.38,1.66,4.38h30.21C400.56,663.83,401.55,662,399.47,659.84Z",
  "M377.74,659.84l-8.48-9a1.21,1.21,0,0,0-.85-.34h-6.67a16.26,16.26,0,0,0-7.38,2.14l-10.68,6.76c-2.19,1.38-1.05,4.38,1.66,4.38h30.21C378.84,663.83,379.82,662,377.74,659.84Z"
];

export const chickenInLegs = (style: string, s: number) => {
  return /*svg*/ `
    <rect style="${style}" ${scaleRectCoords(s, ...legCoords[0])}/>
    <path style="${style}" d="${scalePath(s, legPaths[0])}"/>
    <rect style="${style}" ${scaleRectCoords(s, ...legCoords[1])}/>
    <path style="${style}" d="${scalePath(s, legPaths[1])}"/>
  `;
};

const combPaths = [
  "M306.53,319.87a.37.37,0,0,1-.27-.16c-3.42-5.89-3.49-13.15-2.73-19.93a43.65,43.65,0,0,1,4-15.06c4.05-7.92,11.72-13.55,20.05-16.68,7.29-2.74,15.09-3.75,22.89-4.19a1,1,0,0,1,.7,1.78,34.7,34.7,0,0,0-7.08,7.92,1,1,0,0,0,1.3,1.45,84,84,0,0,1,27.13-8.14,1,1,0,0,1,.9,1.65,51.88,51.88,0,0,0-5.66,8.08,1,1,0,0,0,1.32,1.39,70.69,70.69,0,0,1,23-6.53,1,1,0,0,1,.84,1.71,50,50,0,0,0-6.33,8.22,1,1,0,0,0,1.08,1.54c11-2.27,20.8-8.35,30.27-14.48a1,1,0,0,1,1.56.78c.22,4.67-1.74,9.29-3.66,13.62-3.26,7.36-6.6,14.85-11.91,20.9-9.91,11.28-25.23,16-40,18.92h-.08Z",
  "M367,319c4.73-7.86,7.69-14.38,9.76-23.31,2.67-11.51,2.63-24.68-4.77-33.89a35.87,35.87,0,0,0-12-9.17c-16.54-8.31-38.55-7.75-51.75,5.23a2.19,2.19,0,0,0-.8,1.32c0,.82.75,1.4,1.46,1.81L330,273.43c-9.6-2.22-19.77,2.76-26.17,10.25s-9.68,17.12-12.24,26.63c3.84-3.35,9.55-3.63,14.52-2.49s9.59,3.5,14.49,4.9C336.73,317.3,353,309.83,367,319",
  "M311.78,310.44a71.74,71.74,0,0,0,5.34-27.52c0-3.63-.06-7.87,2.81-10.09,3.48-2.7,9-.08,10.77,3.94s1.05,8.66.27,13L344.48,264a13.29,13.29,0,0,1,3-4.29c4.06-3.39,10.78-.63,13.23,4.06s1.86,10.33,1,15.56q-1.07,6.6-2.53,13.14l20.62-16.91c4.48-3.68,9.57-7.56,15.35-7.19a10.07,10.07,0,0,1,3.7.95,10.71,10.71,0,0,1,4,3.65c4.14,6.1,2.87,14.71-1.36,20.74s-10.87,9.92-17.57,13c-14.28,6.54-30.31,10.15-45.8,7.57-8.82-1.47-17.61-4.91-26.43-3.46",
  "M311,321.22a28.09,28.09,0,1,1,21.49-50.41c5.81-12,19.88-19,33.08-17.44s24.85,11.33,29.65,23.74,2.92,27-4.08,38.27c-5.91,9.55-17.72,17.25-28.08,12.94C364,315,352.79,302,339.46,300.84S312.3,307.68,311,321",
  "M307.43,318.11c-18-12.4-28.19-37.23-21-57.77a1.37,1.37,0,0,1,2.16-.62,147.88,147.88,0,0,0,25.13,16.19,1.37,1.37,0,0,0,2-1.47c-3.59-22.09,9.2-46,29.6-55.18a1.37,1.37,0,0,1,1.91,1.52,94.63,94.63,0,0,0,2.61,47.53,1.37,1.37,0,0,0,2,.75,82.66,82.66,0,0,1,71.85-3.82,1.37,1.37,0,0,1-.31,2.61c-18.55,3.35-38.26,8.58-48.77,23.59a1.38,1.38,0,0,0,.91,2.15,78.34,78.34,0,0,1,53.41,37.34A1.37,1.37,0,0,1,427.8,333c-20.64,1.11-49.78.42-70.13,1.59a1.37,1.37,0,0,1-1.42-1.1c-2.33-11.55-2-19.48-13.52-23.19-11.86-3.84-26.05-.55-35.3,7.81",
  "M307,325c-2.95-9.07-3.76-18.67-.74-27.72s9.7-17,18.48-20.73A19.72,19.72,0,0,1,336.07,275a11.71,11.71,0,0,1,8.75,6.86c3.83-4.18,9.3-7.1,15-6.92s11.32,3.9,12.83,9.37A22.79,22.79,0,0,1,387,280.6c5,.57,9.88,3.46,12.16,8,3,6,1.12,13.16-1.39,19.34a18.59,18.59,0,0,1-4.15,6.88A14.17,14.17,0,0,1,387,318c-7.88,1.82-16.12-.59-23.48-3.94s-14.3-7.69-22-10.06-16.7-2.5-23.29,2.18S308,323,307,325",
  "M310.92,322.2a.32.32,0,0,1-.29-.09c-4.67-5-6.39-12-7.18-18.79-.61-5.19-.79-10.51.47-15.57,2.14-8.63,8.34-15.86,15.73-20.79,6.48-4.33,13.86-7.08,21.35-9.28a1,1,0,0,1,1.09,1.57,34.39,34.39,0,0,0-5.1,9.32,1,1,0,0,0,1.59,1.12,84.32,84.32,0,0,1,24.57-14.09,1,1,0,0,1,1.26,1.41,51,51,0,0,0-3.68,9.15,1,1,0,0,0,1.6,1.06,70.49,70.49,0,0,1,20.91-11.58,1,1,0,0,1,1.2,1.47,50.29,50.29,0,0,0-4.29,9.45,1,1,0,0,0,1.4,1.25c10.16-4.7,18.36-12.85,26.19-21a1,1,0,0,1,1.7.41c1.27,4.5.41,9.44-.48,14.09-1.5,7.91-3,16-6.85,23.06-7.09,13.23-20.95,21.32-34.64,27.5l-.07,0Z",
  "M308.13,314.73c16.6,4.8,30,3,47,.42a269.81,269.81,0,0,0,56.75-15.26c13.46-5.25,27.55-12.65,33.24-25.93a30.37,30.37,0,0,0-43.35-38.12c1.95-6.22-2.24-13.29-8.26-15.78s-13.16-1-18.65,2.48-9.59,8.83-13.05,14.36A108,108,0,0,0,348,270.29c3.66-8.8-5.05-19.2-14.58-19.48s-18,7-22,15.63c-4-10.39-19.83-12.33-27.92-4.69s-8.47,21.14-3.06,30.87,17.39,18,27.74,22.11Z",
  "M312,310a45.13,45.13,0,0,1-7.31-18.33c-1.23-7.27-.27-15.75,5.5-20.34,3.38-2.68,7.89-3.57,12.2-3.37,8.69.41,17.69,6,19.43,14.48,4.25-9.69,17.57-14.06,26.74-8.77s12,19,5.78,27.54a17.14,17.14,0,0,1,16.23,24.21,10.68,10.68,0,0,1-5.35,5.67c-3.66,1.49-7.92-.09-11-2.58s-5.31-5.82-8.08-8.63c-6.7-6.75-16.2-10.14-25.66-11.15s-19.07.12-28.51,1.27"
];

export const chickenInComb = (comb: number, style: string, s: number) => /*svg*/ `
  <path style="${style}" d="${scalePath(s, combPaths[comb - 1])}"/>
`;

const beakPaths = [
  "M315.15,320.48A53.37,53.37,0,0,0,298,322.82c-3.46,1.14-7,2.9-9.45,6.38a26.51,26.51,0,0,0-3.49,8.11c-.33,1.16.54,2.18,1.37,1.63,6.94-4.55,15.15-5.39,22.3-2.21.53.24,1.11-.14,1.31-.86,1.4-5,3.87-10.43,5.07-15.39",
  "M310.67,320.54a67.37,67.37,0,0,0-17,2c-3.41.94-6.87,2.35-9.22,5.09a18.13,18.13,0,0,0-3.22,6.38c-.28.91.44,1.26,1.43,1.26,9.53-.06,18.52-.15,26.51-.24,1,0,.88-1.77.9-2.36.42-13.29.62-8.6.61-12.14",
  "M307.44,319.33l-23,7.88a1.15,1.15,0,0,0,0,2.2l23.1,5.7a1.2,1.2,0,0,0,1.46-1.17l-.08-13.58A1.1,1.1,0,0,0,307.44,319.33Z",
  "M311.5,321.5c-6.61-1.94-14.52-4.35-21.55-6.45a1,1,0,0,0-1,1.7c3.13,2.85,6.45,6.47,9.95,8.85a1,1,0,0,1-.11,1.72c-4.72,2.35-9.32,4-13.76,6.8a1,1,0,0,0,.59,1.85l23.4-1.28a.88.88,0,0,0,1-1l1.14-12.15"
];

export const chickenInBeak = (beak: number, style: string, s: number) => /*svg*/ `
  <path style="${style}" d="${scalePath(s, beakPaths[beak - 1])}"/>
`;

const wattlePath =
  "M306.43,334.36c5.32,5.13,8.13,13.17,7.81,20.55a38.94,38.94,0,0,1-1.54,8.68c-1.32,4.76-3.21,9.57-6.81,12.94-5.08,4.76-12.67,5.82-19.58,5.07-4.12-.45-8.52-1.67-11-5-2.31-3.15-2.32-7.41-1.89-11.29s1.24-7.81,3.78-10.69c3-3.41,7.73-4.58,12-6.24,7-2.75,12.42-8.23,17.24-14";

export const chickenInWattle = (style: string, s: number) => /*svg*/ `
  <path style="${style}" d="${scalePath(s, wattlePath)}"/>
`;

const bodyPaths = [
  "M494,495c-5,2,8-12,9.38-18.64S468,508,414.84,485.31,377,386,377.88,364.52,370,296,333.13,300.62,306.8,336.93,299,358c-10,27-109,60-74.38,159.5,23,66,81.6,90.5,118.48,99.51,4.53,7.84,12.31,13,21.15,13a22.68,22.68,0,0,0,10.87-2.79A22.61,22.61,0,0,0,386,630c7.73,0,14.64-4,19.29-10.19,69-11.05,88.07-58.8,98.11-81C514.76,513.71,514,488,517,481S499,493,494,495Z",
  "M403,528c-57-11-114-31-137-87-6.67-15.83-7.77-34.45-.43-50.05-29.32,25.1-63.51,61.7-40.95,126.55,23,66,81.6,90.5,118.48,99.51,4.53,7.84,12.31,13,21.15,13a22.68,22.68,0,0,0,10.87-2.79A22.61,22.61,0,0,0,386,630c7.73,0,14.64-4,19.29-10.19,69-11.05,88.07-58.8,98.11-81a122.7,122.7,0,0,0,8.05-25.25C480.39,532.48,440.06,534.33,403,528Z",
  "M411.14,597.54a185.74,185.74,0,0,1-71-5.25L339,592c-18-5-33-13-49-22-33.37-18.54-60.71-49.11-72.49-86.13a125.89,125.89,0,0,0,7.11,33.63c23,66,81.6,90.5,118.48,99.51,4.53,7.85,12.31,13,21.15,13a22.68,22.68,0,0,0,10.87-2.79A22.61,22.61,0,0,0,386,630c7.72,0,14.64-3.95,19.28-10.18,45-7.2,68.78-30,82.66-51.21A171.79,171.79,0,0,1,411.14,597.54Z"
];

export const chickenInBody = (bodyStyle: string, shadeStyle: string, s: number) => /*svg*/ `
  <path style="${bodyStyle}" d="${scalePath(s, bodyPaths[0])}"/>
  <path style="${shadeStyle}" d="${scalePath(s, bodyPaths[1])}"/>
  <path style="${shadeStyle}" d="${scalePath(s, bodyPaths[2])}"/>
`;

const eyePaths = [
  "M331.5,334.26a23.78,23.78,0,0,1,11.26,2.7,14.48,14.48,0,1,0-22.06-.24A24,24,0,0,1,331.5,334.26Z",
  "M326.32,334.79a25.63,25.63,0,0,1,5.18-.53,25.93,25.93,0,0,1,5.73.64,9.18,9.18,0,1,0-10.91-.11Z"
];

const eyeCoords: [number, number, number, number] = [334, 324, 3, 3];

export const chickenInEye = (s: number) => /*svg*/ `
  <path style="fill: #fff" d="${scalePath(s, eyePaths[0])}"/>
  <path style="fill: #000" d="${scalePath(s, eyePaths[1])}"/>
  <ellipse style="fill: #fff" ${scaleEllipseCoords(s, ...eyeCoords)}/>
`;

const cheekCoords: [number, number, number, number] = [331.5, 347, 18.5, 13];

export const chickenInCheek = (style: string, s: number) => /*svg*/ `
  <ellipse style="${style}" ${scaleEllipseCoords(s, ...cheekCoords)}/>
`;

const tailPaths = [
  "M387.86,490.81a255.69,255.69,0,0,0,141.23-102.2,1,1,0,0,1,1.85.78,129.17,129.17,0,0,1-33.31,62.7,1,1,0,0,0,.72,1.75A198.11,198.11,0,0,0,577.07,438a1,1,0,0,1,1.13,1.66,159.73,159.73,0,0,1-57,37.5,1,1,0,0,0-.35,1.69,110.94,110.94,0,0,0,53.48,27.95,1,1,0,0,1,.06,2c-17.26,4.77-40.1,9.07-57,5.59a1,1,0,0,0-1.23,1.21c1.5,7.28,7.61,12.59,13.32,18a1,1,0,0,1-.77,1.77C477.92,532,432.35,516.47,388,491",
  "M378.39,502.07a100.73,100.73,0,0,1,130.94-76.62c22.12,7.41,42,23.44,50.65,45.09,4.63,11.58,6,24.21,6.27,36.67.83,35.5-10,75.92-41.87,91.66,3-19.53-.45-40.77-12.93-56.1s-34.9-23.07-53.08-15.32c-4.08,1.74-7.91,4.19-12.25,5.15-7.87,1.73-15.89-1.73-23.1-5.35-18-9-28.24-12.9-44.52-24.75",
  "M423,495c-6.43-7.1-9.54-12-12.51-21.12s-1.3-20.46,6.46-26.06a22.93,22.93,0,0,1,11.82-3.9c4.16-.29,8.56.25,12,2.61s5.6,6.89,4.29,10.85c2.8-8,6-16.09,11.67-22.4s14.24-10.61,22.57-9,15.25,10.37,12.94,18.52c7-5.75,15.44-10.27,24.51-10.88s18.76,3.32,23.3,11.19,2.26,19.48-5.79,23.69c12.27-1.48,24.63,9.12,25,21.47S548.08,513.68,535.74,513c4.25,4.93,7.69,10.84,8.38,17.31s-1.8,13.54-7.27,17.08-13.85,2.37-17.21-3.21c-2,10.29-7,21-16.48,25.36C494,573.82,482.71,571,474.5,565s-14-14.58-19.66-23c-10.64-15.93-21.2-31.06-31.84-47",
  "M358,476c19.49,7.77,75.06-15.74,92.66-27.16a67.08,67.08,0,0,0,29.94-52,1.1,1.1,0,0,1,.71-1c3.33-1.16,6.88,3.68,7,7.24a11.18,11.18,0,0,0,1,4.67c4.15,8.08,11.51,2.46,12-3.14.35-4.26-1.71-8.29-2.93-12.39S497,381,500.39,380.32c6.35-.47,11,5.67,14.16,11.2,18.88,33.14,30.48,73.71,17,109.4-14.11,37.41-56.87,61.58-96.2,54.38-8.14-1.49-16.25-4.26-22.69-9.47C403.55,538.43,383,525,376,514c-12.28-19.29-17-18-18-38",
  "M422.62,518.13C412,506,409.29,488.74,410,472.62c.56-12.43,3-25,8.89-35.95,8-14.89,21.92-25.9,37.05-33.43a126.09,126.09,0,0,1,65.46-12.73.81.81,0,0,1,.56,1.33c-3.29,3.74-9.06,4.62-14,6.18a37.21,37.21,0,0,0-20.64,16.57.78.78,0,0,0,.82,1.17c13.92-2.75,28.1-4.91,42.24-3.74,14.68,1.2,29.48,6.3,40,16.6a26.73,26.73,0,0,1,7.09,10.58.79.79,0,0,1-.79,1l-23-1.4c-9.38-.57-19.42-1-27.61,3.4a.78.78,0,0,0,.18,1.44c13.87,3.67,27.78,8.19,39.37,16.61s20.53,21.31,21.26,35.44a3.05,3.05,0,0,1-2.34,3.15,11.32,11.32,0,0,1-8.45-2c-3.18-2.19-5.5-5.37-8.24-8.08a35.71,35.71,0,0,0-22.49-10.13.78.78,0,0,0-.66,1.27,65.63,65.63,0,0,1,13,52.4.78.78,0,0,1-1.5.11c-3.81-11.35-8.76-23.15-19.18-28.73-1.63-.88-3.67-1.56-5.28-.65a6,6,0,0,0-2.27,3.13c-5.78,13.87-4.81,32.61,7.84,40.71,3.67,2.35,8.44,4.1,10.45,7.68a1.6,1.6,0,0,1-1,2.34l-18.11,4.93a6.58,6.58,0,0,0-3.14,1.82c-3.38,3.65.32,8.3,2.72,12.11,4.89,7.75,4.12,18.56-1.53,25.72a1.77,1.77,0,0,1-2.88-.11c-2.72-4.18-4.47-9-6.6-13.51-8.81-18.71-24.55-33.47-42.09-44.42s-33.36-17.53-52.66-25",
  "M410.67,489.53c22.05-70.84,90.57-124.66,164.62-129.31,8.7-.55,18.42-.1,24.64,6,9.94,9.74,3.75,28.09-8.25,35.13s-26.87,6.12-40.74,5a81.15,81.15,0,0,1,59.52,23.85c6.37,6.45,11.77,14.36,13,23.34s-2.55,19.06-10.63,23.16c-15.22,7.71-31.94-8.54-49-9.19,8.25,10.59,16.8,21.9,18.44,35.22s-6.71,28.84-20.1,29.86c-10.54.8-19.5-7.14-27.06-14.53,2.33,10.83,4.67,22,3.07,32.91s-8,21.93-18.38,25.79c-12.49,4.65-26.37-2.08-36.63-10.59-28.17-23.36-42-56.69-72.7-76.65",
  "M405.94,489.92c4.84-8.69,10.09-17.8,18.74-22.69,6.32-3.58,13.74-4.48,20.79-6.23,12.51-3.12,25-9.85,30.8-21.36,3.78-7.48,4.44-16.4,9.11-23.37,6-8.93,17.65-12.81,28.34-11.72-2.24,3.72-5.78,6.44-8.79,9.58a41.87,41.87,0,0,0-10.44,19c-1.9,7.79-.42,17.78,6.94,21,3.86,1.67,8.42.93,12.18-1s6.85-4.84,9.9-7.74c5-4.72,10-9.59,12.91-15.78,3.87-8.23,3.45-17.73,3.76-26.82s1.76-18.92,8.23-25.31A20.91,20.91,0,0,1,571,373.33c-.11,3.25-3.27,5.38-5.68,7.56-8.77,7.9-9.82,21.15-9.28,32.94s1.88,24.38-3.85,34.7c-7.12,12.84-23.77,19.26-28.18,33.27a11.86,11.86,0,0,0-.18,7.71c1.35,3.56,5,5.68,8.66,6.84,8.47,2.7,19.4.6,23.31-7.38,2.42-4.92,1.63-10.71,2-16.18s2.8-11.73,8.14-13a2.43,2.43,0,0,1,1.51,0c1.33.58,1,2.49.71,3.9-2,8.17,2,16.48,3.08,24.82,2.14,16.29-8.16,33.38-23.57,39.1-5,1.85-10.33,2.59-15.32,4.44-9.18,3.41-16.62,10.33-25.5,14.45-10,4.68-21.58,5.54-32.55,4s-21.51-5.39-31.68-9.79c-8.68-3.75-17.42-8.12-23.65-15.23-9.21-10.51-11.26-22.25-13.18-36.1",
  "M410.31,492.57c8.34-47.4,48.68-87.44,96.14-95.44,4.46-.75,10.92.44,10.63,4.95a6.93,6.93,0,0,1-2.19,4.06c-12,12.8-35.57,13.84-41.71,30.29,28.75-15.65,60.69-31.82,92.72-25.07,3.69.77,7.48,1.95,10.16,4.61s3.82,7.18,1.66,10.27c-1.46,2.09-4,3.09-6.5,3.67-11.54,2.72-23.59-1.06-35.42-.38a47.64,47.64,0,0,0-31.47,14.58c12.15-.38,26.47.29,33.25,10.38a18.65,18.65,0,0,1-2.86,23.42c-1.67,1.51-3.75,2.92-4.18,5.13-.51,2.66,1.6,5,3.31,7.09,5.48,6.72,8.14,16.14,5.29,24.32s-12,14.19-20.39,12.06c3.52,10.94-3.07,23.47-13.24,28.84s-22.78,4.43-33.32-.14-19.33-12.39-27.33-20.64C430.71,520,420.62,510.13,410.5,492.5",
  "M473.52,428.89C446,441,429.82,455,424.41,483s18.64,51.26,31.61,61.62S488,548,496,536s12.48-19.59,12.48-19.59,14.88,3.69,24.2-9.36a25.19,25.19,0,0,0,2.24-25.85s9.6,10.72,21.34,5.76,8.35-20.46,8.35-20.46,11,15.17,20.39,10.5c6-3,7-20-2.94-32.59S549.56,419.21,527,419C498.54,418.73,473.52,428.89,473.52,428.89Z"
];

export const chickenInTail = (tail: number, style: string, s: number) => /*svg*/ `
  <path style="${style}" d="${scalePath(s, tailPaths[tail - 1])}"/>
`;

const wingPaths = [
  [
    "M296.83,459.09c-10.81,23.72-5.49,49.18,4.94,73.81s31.29,43.74,54.91,50.29c5.7,1.58,11.78,2.44,17.25.38s10.08-7.75,9.77-14.24c20.23,15.67,47.25,17.5,70,8.6s41.38-27.43,55.5-49c7.71-11.79,14.39-27.19,8.86-40.81-3.8-9.35-12.66-15.24-21.63-17.41s-18.18-1.19-27.25-.44c-34.55,2.88-71.13,2-102-16.68-15.81-9.57-32.22-23.15-49.43-18.75-3.23.83-14.83,6.43-20.85,24.24",
    "M518,488.13c-3.8-9.35-12.66-15.24-21.63-17.41a48.29,48.29,0,0,0-8.59-1.21c.81,15.1-3.86,30.95-7.93,44.75-16.69,51.85-67.94,30.09-106.21,24.21-9-1-14.62,8.59-22.08,11.8-13.59,4.26-27.94,2.9-41.42-1.87,11.43,17,28.14,29.69,46.52,34.79,5.7,1.58,11.78,2.44,17.25.38s10.08-7.75,9.77-14.24c20.23,15.67,47.25,17.5,70,8.6s41.38-27.43,55.5-49C516.87,517.15,523.55,501.75,518,488.13Z"
  ],
  [
    "M375,582c5.66.4,10.16,9.36,8.19,14.68s-7.86,8.43-13.52,8.59-11.13-2.11-16.11-4.83c-20.62-11.24-36-30.58-45.79-51.94s-14.25-44.76-16.89-68.1c-.83-7.33-1.48-14.74-.75-22.08a34.56,34.56,0,0,1,3.55-12.9c3.58-6.72,10.18-11.44,17.29-14.18s14.75-3.68,22.33-4.43c12.45-1.22,25.1-1.95,37.38.4,15,2.87,28.76,10.18,42.87,16.1,30.3,12.71,64.49,19.18,96.2,10.56,3.27-.89,6.64-1.95,10-1.47,7.76,1.1,12.13,9.81,12.65,17.63.84,12.69-5.08,25.28-14.24,34.11s-21.27,14.15-33.7,16.85q10-1.47,20.14-2.23c3.65-.27,7.73-.34,10.48,2.07,2.6,2.28,3.18,6.25,2.19,9.56s-3.29,6.05-5.75,8.47c-10.68,10.5-25.32,16.45-40.2,18.08s-30-.86-44.23-5.51l15.46,10.28a15,15,0,0,1,5,4.52c2.11,3.56.86,8.37-1.95,11.41s-6.84,4.61-10.82,5.74c-19.34,5.45-39.92,2.17-59.73-1.14",
    "M532.4,470c-.52-7.82-4.89-16.53-12.65-17.63-3.36-.48-6.73.58-10,1.47a114.72,114.72,0,0,1-26.63,3.87c-15.39,32-42.83,57.41-80.12,64.26a100.93,100.93,0,0,1-112.28-67.77c-.25,1.36-.45,2.72-.59,4.09-.73,7.34-.08,14.75.75,22.08,2.64,23.34,7.14,46.74,16.89,68.1s25.17,40.7,45.79,51.94c5,2.72,10.44,5,16.11,4.83s11.56-3.27,13.52-8.59c1.7-4.61-1.45-11.94-6-14.08l-2.15-.36,0-.24a6.07,6.07,0,0,1,2.18.6c19.15,3.18,38.94,6,57.58.78,4-1.13,8-2.71,10.82-5.74s4.06-7.85,1.95-11.41a15,15,0,0,0-5-4.52l-15.46-10.28c14.23,4.65,29.35,7.14,44.23,5.51s29.52-7.58,40.2-18.08c2.46-2.42,4.76-5.17,5.75-8.47s.41-7.28-2.19-9.56c-2.75-2.41-6.83-2.34-10.48-2.07q-10.11.76-20.14,2.23c12.43-2.7,24.53-8,33.7-16.85S533.24,482.72,532.4,470Z",
    "M527.16,456.55C515.39,473.69,503.89,491.1,488,505c-32,26-71,41-112,41a163.75,163.75,0,0,1-76.21-19,166.48,166.48,0,0,0,8,21.49c9.76,21.36,25.17,40.7,45.79,51.94,5,2.72,10.44,5,16.11,4.83s11.56-3.27,13.52-8.59c1.7-4.61-1.45-11.94-6-14.08l-2.15-.36,0-.24a6.07,6.07,0,0,1,2.18.6c19.15,3.18,38.94,6,57.58.78,4-1.13,8-2.71,10.82-5.74s4.06-7.85,1.95-11.41a15,15,0,0,0-5-4.52l-15.46-10.28c14.23,4.65,29.35,7.14,44.23,5.51s29.52-7.58,40.2-18.08c2.46-2.42,4.76-5.17,5.75-8.47s.41-7.28-2.19-9.56c-2.75-2.41-6.83-2.34-10.48-2.07q-10.11.76-20.14,2.23c12.43-2.7,24.53-8,33.7-16.85S533.24,482.72,532.4,470A23.11,23.11,0,0,0,527.16,456.55Z"
  ],
  [
    "M388,462c-33.32-74.53-83-17-89,1-10.81,32.42-2.07,136.28,121.7,134.09s83.34-129.48,59.76-141-1.72,24-9.32,20.64-3.39-15.55-22.9-22.25-2.95,9.41-8.17,9.75-12.92-15.09-23.36-16.35,4,8.17.33,24.51S396.82,481.73,388,462Z",
    "M295.89,495.81c2.94,43,30.43,103,124.81,101.28,72.18-1.28,88.51-45.1,84.91-83.69C481.82,529.45,451.73,534.92,424,538,378.14,542.33,330.05,527.17,295.89,495.81Z",
    "M339,559c-12-4.5-24-11.82-32.64-22,15.06,32.23,48.34,61.22,114.34,60.05,54.57-1,77.22-26.25,83.46-55.21C460.34,580.74,392.79,578.48,339,559Z",
    "M453,478c13.3,10.45,32.92,14.57,45.13,3.81-5.13-13.14-11.91-22.87-17.67-25.67-23.59-11.47-1.72,24-9.32,20.64s-3.39-15.55-22.9-22.25-2.95,9.41-8.17,9.75-12.92-15.09-23.36-16.35,4,8.17.33,24.51c-.09.39-.19.75-.29,1.12,3.25,2,7.07,3.25,11.25,4.44C437,480,446,472,453,478Z"
  ]
];

export const chickenInWing = (
  wing: number,
  wingStyle: string,
  shadeStyle: string,
  tipShadeStyle: string,
  s: number
) => {
  const style = [wingStyle, shadeStyle, shadeStyle, tipShadeStyle];

  return wingPaths[wing - 1]
    .map(
      (p, i) => /*svg*/ `
        <path style="${style[i]}" d="${scalePath(s, p)}"/>
      `
    )
    .join("");
};

const lqtyBandCoords: [number, number, number, number, number][] = [
  [377.33, 638, 17.3, 10, 2],
  [377.33, 642, 17.3, 6, 2],
  [377.33, 641.22, 17.3, 3.57, 0]
];

export const chickenInLQTYBand = (s: number) => {
  return /*svg*/ `
    <rect style="fill: #5bb2e4" ${scaleRectCoords(s, ...lqtyBandCoords[0])}/>
    <rect style="fill: #705ed6" ${scaleRectCoords(s, ...lqtyBandCoords[1])}/>
    <rect style="fill: #2241c4" ${scaleRectCoords(s, ...lqtyBandCoords[2])}/>
  `;
};
