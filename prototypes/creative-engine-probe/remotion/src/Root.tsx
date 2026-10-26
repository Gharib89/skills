import { Composition } from "remotion";
import { Scene } from "./Scene";
import { GpuProbe } from "./GpuProbe";
import { Lit } from "./Lit";
export const Root = () => (
  <>
    <Composition
      id="probe"
      component={Scene}
      durationInFrames={300}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="probe60"
      component={Scene}
      durationInFrames={1800}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="lit"
      component={Lit}
      durationInFrames={120}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="gpu"
      component={GpuProbe}
      durationInFrames={1}
      fps={30}
      width={1920}
      height={200}
    />
  </>
);
