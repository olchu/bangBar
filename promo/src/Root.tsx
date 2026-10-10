import React from "react";
import { Composition } from "remotion";
import { BangBarPromo } from "./BangBarPromo";
import { DURATION, FPS, HEIGHT, WIDTH } from "./theme";

export const Root: React.FC = () => (
  <Composition id="BangBarPromo" component={BangBarPromo} durationInFrames={DURATION} fps={FPS} width={WIDTH} height={HEIGHT} />
);
